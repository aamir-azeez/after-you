extends SceneTree

const Coordinator = preload("res://services/relay_room_coordinator.gd")
const Catalog = preload("res://core/v2/stage_catalog.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const Simulation = preload("res://core/v2/simulation_v2.gd")
const HOST := "HHHHHHHHHHHHHHHHHHHHHH"
const GUEST := "GGGGGGGGGGGGGGGGGGGGGG"
const ROOM := "RRRRRRRRRRRRRRRRRRRRRR"

class Boundary:
	extends RefCounted
	signal release
	var identity := {"ready": true, "player_id": HOST, "epoch": 1}
	var disk: Dictionary = {}
	var requests: Array = []
	var writes: Array = []
	var responses: Array = []
	var fail_load := false
	var fail_save := false
	var wait_response := false
	var all_posts_persisted := true
	var on_save: Callable
	var on_request: Callable
	var key_counter := 0
	func owner() -> Dictionary:
		return identity.duplicate(true)
	func load_store(scope: String) -> Dictionary:
		return {"ok": not fail_load, "found": disk.has(scope), "value": disk.get(scope, {}).duplicate(true)}
	func save_store(scope: String, value: Dictionary) -> Dictionary:
		writes.append(scope)
		if fail_save:
			return {"ok": false}
		disk[scope] = JSON.parse_string(JSON.stringify(value))
		if on_save.is_valid():
			on_save.call()
		return {"ok": true}
	func key() -> String:
		key_counter += 1
		return "synthetic-operation-%04d" % key_counter
	func transport(request: Dictionary) -> Dictionary:
		requests.append(request.duplicate(true))
		if request.method == HTTPClient.METHOD_POST:
			var scope := "relay-room-v2:" + str(request.owner_player_id) + ":" + ROOM
			all_posts_persisted = all_posts_persisted and Canonical.same(disk.get(scope, {}).get("pending", {}).get("body"), request.body)
		if on_request.is_valid():
			on_request.call(request)
		if wait_response:
			await release
		if responses.is_empty():
			return {"ok": false, "status": 0, "code": "connection_interrupted"}
		var response: Variant = responses.pop_front()
		var result: Dictionary = response.call(request) if response is Callable else response.duplicate(true)
		# Actual HTTP and persisted JSON have String keys, not GDScript dot-
		# insertion StringName keys or other engine-only values.
		return JSON.parse_string(JSON.stringify(result))

var checks := 0
var failures := 0
var fixtures: Dictionary = {}
var level := Catalog.relay_isles()

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for name: String in ["relay-a", "relay-b", "garden-a", "garden-b", "initial-checkpoint", "relay-checkpoint", "final-checkpoint"]:
		fixtures[name] = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/v2/" + name + ".json"))
	await _native_validation()
	await _durable_submission()
	await _lost_ack_and_exact_retry()
	await _second_turn_and_fork()
	await _errors_and_drafts()
	await _identity_boundaries()
	await _refresh_scheduling()
	await _untrusted_storage_and_memories()
	await _live_autosave()
	print("Relay room coordinator: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _coordinator(boundary: Boundary):
	return Coordinator.new(boundary.transport, boundary.load_store, boundary.save_store, boundary.owner, boundary.key)

func _open(boundary: Boundary, room: Dictionary = {}):
	var coordinator = _coordinator(boundary)
	_check(coordinator.bind_room(ROOM), "Bind a room using only an injected ready owner")
	boundary.responses.append(_ok(_snapshot(boundary.identity.player_id) if room.is_empty() else room))
	_check(await coordinator.refresh(), "Accept source-verified server snapshot")
	return coordinator

func _snapshot(owner: String = HOST, index: int = 0, has_a: bool = false, revision: int = 1, branch: int = 0) -> Dictionary:
	var checkpoint: Dictionary = fixtures[["initial-checkpoint", "relay-checkpoint", "final-checkpoint"][index]].duplicate(true)
	var first: Variant = HOST if index == 0 else GUEST
	var second: Variant = GUEST if index == 0 else HOST
	var room := {
		"schema_version": 2, "api_version": 2, "room_id": ROOM, "revision": revision,
		"branch": branch, "stage_index": index, "level_id": "relay-isles", "level_version": 2,
		"definition_hash": Canonical.digest(level), "host_id": HOST, "guest_id": GUEST,
		"checkpoint": checkpoint, "a_turn_id": "t%d-%d-a" % [branch, index] if has_a else null,
		"completed_pair_ids": ["p0-0", "p0-1"].slice(0, index),
		"invite_expires_at": "2026-09-21T12:00:00Z", "created_at": "2026-09-14T12:00:00Z", "updated_at": "2026-09-14T12:00:00Z",
		"active_role": "complete" if index == 2 else ("b" if has_a else "a"),
		"first_player_id": null if index == 2 else first,
		"active_player_id": null if index == 2 else (second if has_a else first),
		"player_slot": "p0" if owner == HOST else "p1", "stage_id": "" if index == 2 else level.stages[index].id,
		"recording_a": fixtures["relay-a" if index == 0 else "garden-a"].duplicate(true) if has_a else null,
		"validation": "structural_client_replay_required"
	}
	if owner == HOST:
		room.invite_code = "A1".repeat(10)
	return room

func _receipt(request: Dictionary, room: Dictionary) -> Dictionary:
	var body: Dictionary = request.body
	var operation: String = request.path.get_file()
	var hash_input := body.duplicate(true)
	hash_input.operation = operation
	var is_fork := operation == "fork"
	var recording: Dictionary = body.get("recording", {})
	var index: int = int(body.stage_index) if is_fork else (0 if recording.stage_id == "relay" else 1)
	var branch := int(body.branch) + (1 if is_fork else 0)
	var checkpoint: String = fixtures["initial-checkpoint" if index == 0 else "relay-checkpoint"].checkpoint_hash
	if not is_fork and recording.role == "b":
		checkpoint = body.checkpoint.checkpoint_hash
	return {"receipt": {
		"schema_version": 2, "room_id": ROOM, "idempotency_key": body.idempotency_key,
		"request_hash": Canonical.digest(hash_input), "operation": operation,
		"accepted_revision": int(body.base_revision) + 1, "branch": branch,
		"stage_index": index, "stage_id": level.stages[index].id,
		"turn_id": null if is_fork else "t%d-%d-%s" % [branch, index, recording.role],
		"recording_hash": null if is_fork else recording.recording_hash,
		"pair_id": "p%d-%d" % [branch, index] if not is_fork and recording.role == "b" else null,
		"checkpoint_hash": checkpoint
	}, "room": room.duplicate(true)}

func _native_validation() -> void:
	var boundary := Boundary.new()
	var coordinator = await _open(boundary)
	_check(coordinator.my_turn() and coordinator.role() == "a" and coordinator.stage_id() == "relay", "Fresh host owns stable p0/A")
	_check(coordinator.save_draft(fixtures["relay-a"]), "Actual native A rehearsal persists offline")
	var invalid: Dictionary = fixtures["relay-a"].duplicate(true)
	invalid.actions[0].x = -100
	invalid.recording_hash = _rehash_recording(invalid)
	_check(not coordinator.save_draft(invalid), "Self-rehashed changed actions do not pass replay hashes")
	_check(Canonical.same(coordinator.draft(), fixtures["relay-a"]), "Rejected draft leaves the original intact")
	var wrong := _snapshot(HOST, 1, false, 3)
	wrong.checkpoint.players.p1.x += 1
	var hash_input: Dictionary = wrong.checkpoint.duplicate(true)
	hash_input.erase("checkpoint_hash")
	hash_input.erase("proof")
	wrong.checkpoint.checkpoint_hash = Canonical.digest(hash_input)
	boundary.responses.append(_ok(wrong))
	_check(not await coordinator.refresh(), "Self-hashed checkpoint with fabricated endpoint fails actual proof replay")
	_check(coordinator.stage_id() == "relay", "Invalid future checkpoint never replaces verified state")
	wrong = _snapshot(HOST, 0, true, 2)
	wrong.recording_a = invalid
	boundary.responses.append(_ok(wrong))
	_check(not await coordinator.refresh(), "Incoming A must pass native replay before B can start")
	wrong = _snapshot()
	wrong.api_version = 3
	boundary.responses.append(_ok(wrong))
	_check(not await coordinator.refresh() and not coordinator.draft().is_empty(), "Unsupported version holds the incoming state without losing rehearsal")
	_check(not coordinator.my_turn() and not await coordinator.commit(fixtures["relay-a"]), "Unsupported incoming version blocks new mutations using an older cached snapshot")
	boundary.responses.append(_ok(_snapshot()))
	_check(await coordinator.refresh() and coordinator.my_turn(), "A fresh supported snapshot explicitly clears the transient remote hold")
	var alone := _snapshot()
	alone.guest_id = null
	boundary = Boundary.new()
	coordinator = await _open(boundary, alone)
	_check(coordinator.my_turn(), "Host may rehearse A before a friend joins")

func _durable_submission() -> void:
	var boundary := Boundary.new()
	var coordinator = await _open(boundary)
	_check(coordinator.last_receipt().is_empty(), "An unsubmitted rehearsal exposes no accepted operation")
	boundary.fail_save = true
	var before := boundary.requests.size()
	_check(not await coordinator.commit(fixtures["relay-a"]), "Failed pending write prevents submission")
	_check(boundary.requests.size() == before, "No POST is sent until exact pending request is durable")
	boundary.fail_save = false
	boundary.responses.append(func(request: Dictionary) -> Dictionary: return _ok(_receipt(request, _snapshot(HOST, 0, true, 2))))
	_check(await coordinator.commit(fixtures["relay-a"]), "Matching receipt commits actual A")
	var accepted_receipt: Dictionary = coordinator.last_receipt()
	_check(accepted_receipt.operation == "turns" and accepted_receipt.recording_hash == fixtures["relay-a"].recording_hash, "Optional features receive the exact accepted turn receipt")
	accepted_receipt.recording_hash = "changed-copy"
	_check(coordinator.last_receipt().recording_hash == fixtures["relay-a"].recording_hash, "Receipt access never exposes mutable gameplay state")
	_check(boundary.all_posts_persisted and coordinator.pending().is_empty(), "POST body was persisted first; receipt clears pending only afterward")
	_check(coordinator.role() == "b" and not coordinator.my_turn(), "Host waits after accepted A")
	_check(boundary.writes.all(func(scope: String) -> bool: return scope == "relay-room-v2:" + HOST + ":" + ROOM), "Only the explicitly owner/room-scoped store is accessed")
	_check(not JSON.stringify(boundary.disk).contains("device_token"), "Coordinator saves no device credential field")
	coordinator.invalidate_identity()
	_check(coordinator.last_receipt().is_empty(), "Identity invalidation removes access to the former player's receipt")
	boundary = Boundary.new()
	coordinator = await _open(boundary)
	boundary.on_request = func(request: Dictionary) -> void:
		if request.method == HTTPClient.METHOD_POST:
			boundary.fail_save = true
	boundary.responses.append(func(request: Dictionary) -> Dictionary: return _ok(_receipt(request, _snapshot(HOST, 0, true, 2))))
	_check(not await coordinator.commit(fixtures["relay-a"]), "Lost local receipt write remains incomplete")
	_check(not coordinator.pending().is_empty() and not boundary.disk.values()[0].pending.is_empty(), "Receipt write failure retains both memory and disk pending request")
	var original: Dictionary = boundary.requests.back()
	boundary.on_request = Callable()
	boundary.fail_save = false
	boundary.responses.append(_ok(_receipt(original, _snapshot(HOST, 0, true, 2))))
	_check(await coordinator.reconcile(), "Exact receipt can finish after local disk recovers")

func _lost_ack_and_exact_retry() -> void:
	var boundary := Boundary.new()
	var coordinator = await _open(boundary)
	_check(not await coordinator.commit(fixtures["relay-a"]), "Lost server response leaves submission unresolved")
	var sent: Dictionary = boundary.requests.back().duplicate(true)
	var expected: Dictionary = coordinator.pending().duplicate(true)
	_check(not coordinator.archive_held_submission(), "An uncertain submission cannot be discarded")
	coordinator = _coordinator(boundary)
	_check(coordinator.bind_room(ROOM) and Canonical.same(coordinator.pending(), expected), "Restart loads the exact request, key and evidence")
	boundary.responses.append(_ok(_snapshot(HOST, 1, false, 3)))
	_check(await coordinator.refresh() and not coordinator.pending().is_empty(), "Later checkpoint alone does not stand in for the pending receipt")
	boundary.responses.append(_ok(_receipt(sent, _snapshot(HOST, 0, true, 2))))
	_check(await coordinator.reconcile(), "Old exact receipt remains valid after a newer checkpoint was fetched")
	_check(coordinator.snapshot().revision == 3 and coordinator.stage_id() == "garden", "Delayed receipt does not roll verified room state backward")
	boundary = Boundary.new()
	coordinator = await _open(boundary)
	await coordinator.commit(fixtures["relay-a"])
	sent = boundary.requests.back().duplicate(true)
	coordinator = _coordinator(boundary)
	_check(coordinator.bind_room(ROOM), "Second lost-ack state loads")
	boundary.responses.append(_error(404, "operation_not_found"))
	boundary.responses.append(func(request: Dictionary) -> Dictionary: return _ok(_receipt(request, _snapshot(HOST, 0, true, 2))))
	_check(await coordinator.reconcile(), "Missing receipt permits one exact retry")
	_check(Canonical.same(boundary.requests.back(), sent), "Retry keeps method, owner, revision, key and complete body identical")
	boundary = Boundary.new()
	coordinator = await _open(boundary)
	boundary.responses.append(func(request: Dictionary) -> Dictionary:
		var value := _receipt(request, _snapshot(HOST, 0, true, 2))
		value.receipt.recording_hash = "0".repeat(64)
		return _ok(value))
	_check(not await coordinator.commit(fixtures["relay-a"]) and coordinator.last_code == "receipt_mismatch", "Receipt for different content is not acceptance")
	_check(not coordinator.pending().is_empty(), "Mismatched receipt preserves exact pending request")

func _second_turn_and_fork() -> void:
	var boundary := Boundary.new()
	boundary.identity.player_id = GUEST
	var coordinator = await _open(boundary, _snapshot(GUEST, 0, true, 2))
	_check(coordinator.my_turn() and coordinator.prior_recording().recording_hash == fixtures["relay-a"].recording_hash, "Guest B uses exact verified first contribution")
	boundary.responses.append(func(request: Dictionary) -> Dictionary: return _ok(_receipt(request, _snapshot(GUEST, 1, false, 3))))
	_check(await coordinator.commit(fixtures["relay-b"]), "B atomically commits actual pair and checkpoint")
	_check(Canonical.same(boundary.requests.back().body.checkpoint, fixtures["relay-checkpoint"]), "B sends the native-derived proof, never a guessed endpoint")
	_check(coordinator.role() == "a" and coordinator.my_turn(), "Stable guest p1 becomes A in second stage")
	boundary.responses.append(func(request: Dictionary) -> Dictionary: return _ok(_receipt(request, _snapshot(GUEST, 1, true, 4))))
	_check(await coordinator.commit(fixtures["garden-a"]), "Guest's next contribution remains the same physical player")
	boundary.identity.player_id = HOST
	boundary.identity.epoch += 1
	coordinator.invalidate_identity()
	_check(coordinator.bind_room(ROOM), "Fresh host binding uses a distinct owner cache")
	boundary.responses.append(_ok(_snapshot(HOST, 1, true, 4)))
	_check(await coordinator.refresh(), "Host verifies full earlier checkpoint chain before final B")
	boundary.responses.append(func(request: Dictionary) -> Dictionary: return _ok(_receipt(request, _snapshot(HOST, 2, false, 5))))
	_check(await coordinator.commit(fixtures["garden-b"]) and coordinator.chapter_complete(), "Final verified B completes the two-pair chapter")
	_check(not await coordinator.commit(fixtures["garden-b"]), "Completed chapter cannot accidentally send another recording")
	boundary.responses.append(func(request: Dictionary) -> Dictionary: return _ok(_receipt(request, _snapshot(HOST, 1, false, 6, 1))))
	_check(await coordinator.fork(1), "Fork receipt restarts reached checkpoint in a new branch")
	_check(coordinator.snapshot().branch == 1 and coordinator.snapshot().completed_pair_ids == ["p0-0"], "Fork preserves prior pair prefix and resets later contribution")
	_check(not await coordinator.fork(1), "Empty current stage has nothing to replace")

func _errors_and_drafts() -> void:
	var boundary := Boundary.new()
	var coordinator = await _open(boundary)
	_check(coordinator.save_draft(fixtures["relay-a"]), "Rehearsal exists before a concurrent fork")
	boundary.responses.append(_ok(_snapshot(HOST, 0, false, 3, 1)))
	_check(await coordinator.refresh(), "A verified different branch can be fetched")
	_check(coordinator.draft().is_empty() and coordinator.held_drafts().size() == 1, "Prior-branch rehearsal is held separately, not replayed against replacement context")
	boundary.responses.append(_error(409, "stale_revision"))
	_check(not await coordinator.commit(fixtures["relay-a"]), "Definitive stale revision is visible")
	_check(coordinator.pending().held and coordinator.last_code == "stale_revision", "Mutation rejection keeps exact request held")
	_check(coordinator.archive_held_submission() and coordinator.held_drafts().size() == 2, "Explicit archive preserves rejected contribution for review")
	boundary.responses.append(_error(503, "v2_mutations_disabled"))
	_check(not await coordinator.commit(fixtures["relay-a"]), "Disabled mutations are not reported as a successful commit")
	_check(not coordinator.pending().held and not coordinator.archive_held_submission(), "Service pause does not falsely resolve uncertain request")
	_check(not coordinator.bind_room("N".repeat(22)), "Cannot redirect an unresolved request to a different room")
	boundary.responses.append(_error(401, "invalid_identity"))
	_check(not await coordinator.reconcile(), "Authentication loss requests recovery")
	_check(coordinator.snapshot().is_empty() and not coordinator.pending().held, "Revoked auth hides room state without pretending old POST was rejected")
	_check(not coordinator.archive_held_submission(), "Auth error never grants permission to discard uncertain pending")

func _identity_boundaries() -> void:
	for recovery: bool in [false, true]:
		var boundary := Boundary.new()
		var coordinator = await _open(boundary)
		boundary.wait_response = true
		boundary.responses.append(_ok(_snapshot(HOST, 0, true, 2)))
		var result := {"done": false, "value": true}
		_refresh_into(coordinator, result)
		_check(coordinator.busy() and not result.done, "An injected asynchronous request is in flight")
		var writes := boundary.writes.size()
		boundary.identity.epoch += 1
		if not recovery:
			boundary.identity.player_id = GUEST
		coordinator.invalidate_identity()
		boundary.wait_response = false
		boundary.release.emit()
		await process_frame
		_check(result.done and not result.value and coordinator.snapshot().is_empty(), "Old response cannot revive cache after recovery/account switch")
		_check(boundary.writes.size() == writes, "Late response does not persist under any owner")
		_check(coordinator.bind_room(ROOM), "Current identity may explicitly reload its own scoped data")
		_check(coordinator.snapshot().is_empty() if not recovery else coordinator.snapshot().revision == 1, "Different owner sees no prior cache; same-owner recovery sees only its prior verified state")
	var boundary := Boundary.new()
	var coordinator = await _open(boundary)
	boundary.wait_response = true
	var result := {"done": false, "value": true}
	_commit_into(coordinator, fixtures["relay-a"], result)
	_check(not coordinator.pending().is_empty(), "Mutation is persisted before its response can be interrupted")
	boundary.identity.ready = false
	boundary.release.emit()
	await process_frame
	_check(result.done and not result.value and coordinator.pending().is_empty(), "Identity deletion invalidates outstanding mutation callback")
	_check(not boundary.disk.values()[0].pending.is_empty(), "Old-owner pending remains scoped for deliberate same-owner recovery, never copied to new owner")
	boundary = Boundary.new()
	coordinator = await _open(boundary)
	boundary.on_save = func() -> void: boundary.identity.epoch += 1
	_check(not coordinator.save_draft(fixtures["relay-a"]) and coordinator.snapshot().is_empty(), "Identity change inside injected persistence cannot restore exposed old state")
	boundary.on_save = Callable()

func _refresh_scheduling() -> void:
	var boundary := Boundary.new()
	var coordinator = await _open(boundary)
	_check(coordinator.last_refresh_result() == {"status": 200, "retry_after_ms": 0, "terminal": false}, "Successful refresh exposes scheduling metadata without its payload")
	boundary.responses.append({"ok": false, "status": 429, "code": "rate_limited", "retry_after_ms": 120000, "data": {"private": "not-retained"}})
	_check(not await coordinator.refresh(), "Rate-limited refresh remains unsuccessful")
	var metadata: Dictionary = coordinator.last_refresh_result()
	_check(metadata == {"status": 429, "retry_after_ms": 120000, "terminal": false}, "Server cooldown survives the coordinator boolean API without response data")
	metadata.retry_after_ms = 0
	_check(coordinator.last_refresh_result().retry_after_ms == 120000, "Scheduling accessor cannot mutate the coordinator result")
	for status: int in [401, 403, 404, 410]:
		boundary.responses.append({"ok": false, "status": status, "code": "unavailable"})
		_check(not await coordinator.refresh() and coordinator.last_refresh_result().terminal, "Terminal HTTP status stops polling: %d" % status)
	boundary.responses.append({"ok": false, "status": 503, "code": "unavailable", "retry_after_ms": 999999999})
	_check(not await coordinator.refresh() and coordinator.last_refresh_result() == {"status": 503, "retry_after_ms": 86400000, "terminal": false}, "Transient failure replaces terminal metadata with a bounded cooldown")
	coordinator.invalidate_identity()
	_check(coordinator.last_refresh_result().is_empty(), "Identity invalidation clears transient scheduling metadata")
	_check(coordinator.bind_room(ROOM) and coordinator.last_refresh_result().is_empty(), "Binding a room does not restore prior transport status from disk")
	boundary.responses.append(_ok(_snapshot()))
	_check(await coordinator.refresh() and coordinator.last_refresh_result().retry_after_ms == 0, "New successful refresh contains no stale cooldown")
	boundary.identity.epoch += 1
	_check(not await coordinator.refresh() and coordinator.last_refresh_result().is_empty(), "An ignored old-owner refresh exposes no stale status")


func _untrusted_storage_and_memories() -> void:
	var boundary := Boundary.new()
	var coordinator = await _open(boundary)
	var scope: String = boundary.disk.keys()[0]
	boundary.disk[scope].api_version = 99
	var original: Dictionary = boundary.disk.duplicate(true)
	coordinator = _coordinator(boundary)
	_check(not coordinator.bind_room(ROOM) and coordinator.read_only, "Unknown saved schema remains read-only")
	_check(Canonical.same(boundary.disk, original) and not await coordinator.refresh(), "Unknown data is neither overwritten nor uploaded")
	boundary = Boundary.new()
	boundary.fail_load = true
	coordinator = _coordinator(boundary)
	_check(not coordinator.bind_room(ROOM) and boundary.writes.is_empty(), "Unreadable local save does not become a fresh writable state")
	boundary = Boundary.new()
	coordinator = await _open(boundary, _snapshot(HOST, 2, false, 5))
	var pair := {"pair_id": "p0-0", "branch": 0, "stage_index": 0, "a": fixtures["relay-a"], "b": fixtures["relay-b"], "checkpoint": fixtures["relay-checkpoint"]}
	boundary.responses.append(_ok(pair))
	var writes := boundary.writes.size()
	_check(not (await coordinator.fetch_pair("p0-0")).is_empty(), "Historical pair is returned only after complete native replay verification")
	_check(boundary.writes.size() == writes, "Memory replay reads do not change live progression")
	pair = pair.duplicate(true)
	pair.branch = "0"
	boundary.responses.append(_ok(pair))
	_check((await coordinator.fetch_pair("p0-0")).is_empty(), "Malformed numeric archive metadata is not silently coerced")
	pair.branch = 0
	pair.b.source_recording_hash = "0".repeat(64)
	boundary.responses.append(_ok(pair))
	_check((await coordinator.fetch_pair("p0-0")).is_empty(), "Memory with a substituted A reference cannot be played")
	_check(coordinator.chapter_complete(), "Rejected memory leaves completed room unchanged")

func _live_autosave() -> void:
	var boundary := Boundary.new()
	var coordinator = await _open(boundary, _snapshot(HOST, 1, true, 4))
	var live: RefCounted = coordinator.create_live_simulation()
	_check(live != null, "Coordinator creates the exact replay-verified local engine for its own turn")
	var unrelated := Simulation.new()
	unrelated.reset(level, "garden", fixtures["relay-checkpoint"], fixtures["garden-a"], "b")
	unrelated.step()
	_check(not coordinator.save_live_draft(unrelated), "An unrelated but valid engine cannot use the fast path")
	var inputs := Simulation.expand_recording_inputs(fixtures["garden-b"])
	var timings: Array[float] = []
	for target: int in [10, 20, 30]:
		while live.tick < target:
			live.step(inputs[live.tick])
		var start := Time.get_ticks_usec()
		_check(coordinator.save_live_draft(live), "Growing registered rehearsal persists without replaying all ancestors")
		timings.append(float(Time.get_ticks_usec() - start) / 1000.0)
	_check(coordinator.role() == "b" and coordinator.pending().is_empty() and boundary.requests.size() == 1, "Autosave neither advances progress nor makes a network request")
	var recording: Dictionary = live.export_recording()
	var resumed = _coordinator(boundary)
	_check(resumed.bind_room(ROOM) and Canonical.same(resumed.draft(), recording), "Restart fully replays the live draft before exposing it")
	var start := Time.get_ticks_usec()
	_check(coordinator.save_draft(recording), "External dictionary save retains full replay verification")
	var replay_ms := float(Time.get_ticks_usec() - start) / 1000.0
	print("RELAY ROOM TIMING ms (desktop headless, in-memory atomic adapter, stage2 30-tick draft): " + JSON.stringify({"live_autosave_samples": timings, "fully_verified_save": replay_ms}))
	_check(not coordinator.save_live_draft(live), "External replacement retires the earlier live engine")
	live = coordinator.create_live_simulation()
	live.step()
	_check(coordinator.save_live_draft(live), "Replacement engine is registered explicitly")
	live.reset(level, "garden", fixtures["relay-checkpoint"], fixtures["garden-a"], "b")
	live.step()
	_check(not coordinator.save_live_draft(live) and coordinator.last_code == "reset_rehearsal", "Resetting the same engine to identical values still invalidates its registration")
	for mutation: String in ["checkpoint", "prior", "stage", "definition"]:
		live = coordinator.create_live_simulation()
		live.step()
		var before := boundary.disk.duplicate(true)
		match mutation:
			"checkpoint": live.get("_checkpoint").players.p0.x += 1
			"prior": live.get("_prior").outcome.threw_seed = false
			"stage": live.stage.flight_ticks += 1
			"definition": live.level.seed_wait_ticks += 1
		_check(not coordinator.save_live_draft(live) and Canonical.same(before, boundary.disk), "Changed live " + mutation + " cannot reuse stale hashes")
	live = coordinator.create_live_simulation()
	live.step()
	boundary.responses.append(_ok(_snapshot(HOST, 1, true, 6, 1)))
	_check(await coordinator.refresh() and not coordinator.save_live_draft(live), "Another branch invalidates an existing live engine")
	live = coordinator.create_live_simulation()
	live.step()
	boundary.identity.epoch += 1
	_check(not coordinator.save_live_draft(live) and coordinator.snapshot().is_empty(), "Recovery invalidates live engine even before explicit caller cleanup")
	boundary = Boundary.new()
	coordinator = await _open(boundary)
	live = coordinator.create_live_simulation()
	live.step()
	boundary.fail_save = true
	_check(not coordinator.save_live_draft(live) and coordinator.draft().is_empty(), "Live I/O failure cannot advance saved draft or accepted progress")
	boundary.fail_save = false
	live.get("_players")[live.active_slot].x += 80
	_check(coordinator.save_live_draft(live), "Registered internal state can only enter draft storage, never acceptance")
	var before := boundary.requests.size()
	_check(not await coordinator.commit(live.export_recording()) and boundary.requests.size() == before, "Corrupt internal live state cannot bypass native replay at commit")
	_check(coordinator.draft().is_empty() and coordinator.read_only, "Even same-process draft resume replays and holds a corrupt live state")
	resumed = _coordinator(boundary)
	_check(not resumed.bind_room(ROOM) and resumed.read_only, "Restart holds a corrupt live draft without replacing its persisted data")

func _refresh_into(coordinator, result: Dictionary) -> void:
	result.value = await coordinator.refresh()
	result.done = true

func _commit_into(coordinator, recording: Dictionary, result: Dictionary) -> void:
	result.value = await coordinator.commit(recording)
	result.done = true

func _rehash_recording(recording: Dictionary) -> String:
	var value := recording.duplicate(true)
	value.erase("recording_hash")
	return Canonical.digest(value)

func _ok(data: Dictionary) -> Dictionary:
	return {"ok": true, "status": 200, "data": data}

func _error(status: int, code: String) -> Dictionary:
	return {"ok": false, "status": status, "code": code}

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
