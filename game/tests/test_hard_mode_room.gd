extends "res://tests/test_relay_room_coordinator.gd"
## Hard rooms on the phone (services/hard_room_client.gd, services/hard_run.gd,
## the coordinator's hard view): the room says it is hard; a slip drops the
## turn's draft (never a held draft, however many slips), keeps the run and
## keeps the reset until the server answers it, byte for byte; a turn refused
## after the room started again goes quietly; the friend reads who slipped
## once, only after a new failure; a room with no space left says so; the
## session asks the server for a hard room only where it hosts them.
const HardMode = preload("res://services/hard_mode.gd")
const HardRun = preload("res://services/hard_run.gd")
const HardRoomClient = preload("res://services/hard_room_client.gd")
const TurnTries = preload("res://services/turn_tries.gd")
const Session = preload("res://services/relay_online_session.gd")
const RoomsApi = preload("res://services/rooms_api.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const KEY := "relay-isles@2"
const Typed = preload("res://services/typed_values.gd")

class FakeApi extends Node:
	var player_id := HOST
	var device_token := "synthetic-device-token"
	var base_url := "https://synthetic.invalid"
	var calls: Array = []
	var answers: Array = []
	func request_json(method: int, path: String, body: Dictionary = {}, _still: Callable = Callable()) -> Dictionary:
		calls.append({"method": method, "path": path, "body": JSON.parse_string(JSON.stringify(body))})
		if answers.is_empty(): return {"ok": false, "status": 0, "code": "connection_interrupted"}
		var answer: Variant = answers.pop_front()
		return JSON.parse_string(JSON.stringify(answer.call(calls.back()) if answer is Callable else answer))

class MemoryStore extends RefCounted:
	var values: Dictionary = {}
	func load_scope(scope: String) -> Dictionary:
		return {"ok": true, "found": values.has(scope), "value": values.get(scope, {}).duplicate(true)}
	func save_scope(scope: String, value: Dictionary) -> Dictionary:
		values[scope] = JSON.parse_string(JSON.stringify(value))
		return {"ok": true}

## The online session as hard_run.gd reads it: a coordinator and a hard client.
class SessionStub extends RefCounted:
	var coordinator: RefCounted
	var room_client: RefCounted
	func hard_client() -> RefCounted: return room_client

var _paths: Array[String] = []

func _run() -> void:
	for name: String in ["relay-a", "relay-b", "garden-a", "garden-b", "initial-checkpoint", "relay-checkpoint", "final-checkpoint"]:
		fixtures[name] = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/v2/" + name + ".json"))
	await _hard_view()
	await _reset_journal()
	await _slips_never_held()
	await _stale_turn_after_reset()
	await _friend_reads_once()
	_room_full()
	_session_body()
	for path: String in _paths:
		for suffix: String in ["", ".tmp", ".backup"]: DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	for suffix: String in ["", ".tmp", ".backup"]: DirAccess.remove_absolute(ProjectSettings.globalize_path(HardMode.runs_path(KEY) + suffix))
	print("Hard mode room: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _path(label: String) -> String:
	var path := "user://hard-room-test-%s-%s.json" % [label, Crypto.new().generate_random_bytes(6).hex_encode()]
	_paths.append(path)
	_paths.append(path.get_basename() + "-open.json")
	return path

func _hard(room: Dictionary, failures_count: int = 0, last: Variant = null, over: bool = false) -> Dictionary:
	var value := room.duplicate(true)
	value["hard"] = {"schema_version": 1, "failures": failures_count, "over": over, "last": last}
	# As the server sends it: String keys and JSON numbers.
	return JSON.parse_string(JSON.stringify(value))

func _last(by: String, stage: int = 0, reason: String = "failed_turn", role: String = "a") -> Dictionary:
	return {"by": by, "stage_index": stage, "role": role, "reason": reason, "at": "2026-10-19T07:00:00.000Z"}

func _identity() -> Dictionary:
	return {"ready": true, "player_id": HOST, "epoch": 1}

func _hard_view() -> void:
	var boundary := Boundary.new()
	var coordinator = await _open(boundary, _hard(_snapshot(HOST)))
	_check(coordinator.snapshot().get("hard") is Dictionary, "A hard room's snapshot says so and is kept")
	boundary.responses.append(_ok(_hard(_snapshot(HOST, 0, false, 2), 1, {"by": "SSSSSSSSSSSSSSSSSSSSSS", "stage_index": 0, "role": "a", "reason": "drowned", "at": "x"})))
	_check(not await coordinator.refresh() and int(coordinator.snapshot().revision) == 1, "A hard view naming someone outside the room is refused")
	boundary.responses.append(_ok(_hard(_snapshot(HOST, 0, false, 3), 1, _last(GUEST))))
	_check(await coordinator.refresh() and int(coordinator.snapshot().hard.failures) == 1, "A slip the room keeps reads in a refresh")
	_check(coordinator.adopt_snapshot(_hard(_snapshot(HOST, 0, false, 4, 1), 2, _last(HOST))) and int(coordinator.snapshot().branch) == 1, "A room a reset returned is taken as a refresh would take it: " + coordinator.last_code)
	_check(not coordinator.adopt_snapshot(_hard(_snapshot(HOST, 0, false, 3), 1, _last(GUEST))), "An older room is never taken back")
	var plain_boundary := Boundary.new()
	var plain = await _open(plain_boundary)
	_check(not plain.snapshot().has("hard"), "An ordinary room has no hard field")

func _reset_answer(request: Dictionary, room: Dictionary, failures_count: int) -> Dictionary:
	var body: Dictionary = request.body
	var next := _hard(room, failures_count, _last(HOST, int(body.stage_index), str(body.reason), str(body.role)))
	return {"ok": true, "status": 200, "data": {"room": next, "failure": _last(HOST, int(body.stage_index), str(body.reason), str(body.role))}}

func _reset_journal() -> void:
	var api := FakeApi.new()
	root.add_child(api)
	var store := MemoryStore.new()
	var client := HardRoomClient.new(api, _identity, store)
	_check(client.bind(ROOM) and client.pending().is_empty() and client.seen() == 0, "A room starts with no reset waiting")
	var room := _hard(_snapshot(HOST, 0, true, 5))
	_check(client.queue_reset(room, "failed_turn", fixtures["relay-a"]), "A slip's reset is kept before it is sent")
	var kept: Dictionary = client.pending()
	_check(kept.base_revision == 5 and kept.branch == 0 and kept.stage_index == 0 and kept.role == "b" and kept.slip.recording_hash == fixtures["relay-a"].recording_hash, "The reset names the room it was played on and carries the slip")
	_check(not client.queue_reset(room, "retry", {}), "One reset waits at a time")
	var answer: Dictionary = await client.send()
	_check(not answer.ok and not answer.get("settled", false) and Typed.same(client.pending(), kept), "Offline, the reset stays")
	var reloaded := HardRoomClient.new(api, _identity, store)
	_check(reloaded.bind(ROOM) and Typed.same(reloaded.pending(), kept), "The kept reset survives the app closing")
	api.answers.append(func(request: Dictionary) -> Dictionary: return _reset_answer(request, _snapshot(HOST, 0, false, 6, 1), 1))
	answer = await reloaded.send()
	_check(answer.ok and reloaded.pending().is_empty() and reloaded.seen() == 1, "Once answered the reset is done and its failure is seen")
	_check(api.calls[-1].path == "/v2/rooms/%s/hard-reset" % ROOM and Typed.same(api.calls[-1].body, api.calls[-2].body), "The resend is byte for byte the first send")
	reloaded.queue_reset(_hard(_snapshot(HOST, 0, false, 6, 1), 1, _last(HOST)), "retry", {})
	api.answers.append({"ok": false, "status": 409, "code": "stale_revision"})
	answer = await reloaded.send()
	_check(not answer.ok and answer.settled and reloaded.pending().is_empty(), "A reset the room moved past is dropped, not resent forever")
	reloaded.queue_reset(_hard(_snapshot(HOST, 0, false, 6, 1), 1, _last(HOST)), "retry", {})
	api.answers.append({"ok": false, "status": 503, "code": "service_unavailable"})
	answer = await reloaded.send()
	_check(not answer.ok and not reloaded.pending().is_empty(), "An outage keeps the reset")
	api.answers.append({"ok": true, "status": 200, "data": {"room": _snapshot(HOST, 0, false, 7, 2), "failure": _last(HOST)}})
	answer = await reloaded.send()
	_check(not answer.ok and not reloaded.pending().is_empty(), "An answer that does not show the reset keeps it")
	api.player_id = GUEST
	_check(reloaded.pending().is_empty() and not reloaded.bind(ROOM), "Another identity never sees or sends this player's reset")
	api.queue_free()

func _coordinator_with_draft(boundary: Boundary, room: Dictionary):
	var coordinator = await _open(boundary, room)
	var live: RefCounted = coordinator.create_live_simulation()
	for input: Dictionary in Simulation.expand_recording_inputs(fixtures["relay-a"]): live.step(input)
	_check(coordinator.save_live_draft(live), "A draft of the slipping turn is saved")
	return coordinator

func _slips_never_held() -> void:
	var boundary := Boundary.new()
	var api := FakeApi.new()
	root.add_child(api)
	var store := MemoryStore.new()
	var stub := SessionStub.new()
	stub.room_client = HardRoomClient.new(api, _identity, store)
	var tries := TurnTries.new(_path("slips"))
	var revision := 1
	stub.coordinator = await _coordinator_with_draft(boundary, _hard(_snapshot(HOST, 0, false, revision)))
	var run: RefCounted = HardRun.for_room(stub, _path("slips-marks"))
	_check(run.active() and run.together and run.tries_key(KEY) == KEY, "A hard room's run is hard and counts tries per room")
	for slip in range(6):
		var slot := TurnTries.slot_for(stub.coordinator, KEY, true)
		tries.start(slot)
		tries.start(slot)
		_check(run.fail_together("retry", {}, tries, slot, "Sam"), "Slip %d keeps its reset" % slip)
		_check(stub.coordinator.draft().is_empty() and stub.coordinator.held_drafts().is_empty(), "Slip %d drops the turn's draft and holds none" % slip)
		_check(tries.count(slot) == 0 and run.reset_pending(), "Slip %d closes the turn's count and waits for its reset" % slip)
		api.answers.append(func(request: Dictionary) -> Dictionary: return _reset_answer(request, _snapshot(HOST, 0, false, request.body.base_revision + 1, request.body.branch + 1 if slip % 2 == 0 else request.body.branch), slip + 1))
		var answer: Dictionary = await run.send_reset()
		_check(answer.ok and not run.reset_pending() and int(stub.coordinator.snapshot().hard.failures) == slip + 1, "Slip %d moves the room back to the start" % slip)
		# The next turn is played and abandoned with a draft again.
		var live: RefCounted = stub.coordinator.create_live_simulation()
		for index in range(60): live.step({"move_x": 0.0, "move_z": 0.0, "interact": false})
		stub.coordinator.save_live_draft(live)
	_check(stub.coordinator.held_drafts().is_empty(), "Six slips later the room holds no drafts and can go on")
	# The friend's reset arriving under a draft of this phone's own drops it too.
	var snapshot: Dictionary = stub.coordinator.snapshot()
	_check(not stub.coordinator.draft().is_empty() and stub.coordinator.adopt_snapshot(_hard(_snapshot(HOST, 0, false, int(snapshot.revision) + 1, int(snapshot.branch) + 1), 7, _last(GUEST))), "A reset from the friend is taken over a draft")
	_check(stub.coordinator.draft().is_empty() and stub.coordinator.held_drafts().is_empty(), "A hard room's old run leaves no draft and no held draft")
	var kept := HardMode.runs(KEY).filter(func(item: Dictionary) -> bool: return item.mode == HardMode.TOGETHER)
	_check(kept.size() == HardMode.MAX_FAILED and kept[-1].friend == "Sam" and kept[-1].by == "you", "The phone keeps the newest five failed runs with the friend's name")
	api.queue_free()

func _stale_turn_after_reset() -> void:
	var boundary := Boundary.new()
	var coordinator = await _open(boundary, _hard(_snapshot(HOST)))
	boundary.responses.append(_error(409, "stale_revision"))
	_check(not await coordinator.commit(fixtures["relay-a"]) and coordinator.pending().get("held", false), "A turn sent after the room started again is refused and held")
	_check(coordinator.drop_held_submission() and coordinator.pending().is_empty() and coordinator.held_drafts().is_empty(), "In a hard room it goes quietly, never into the held drafts")
	var plain := Boundary.new()
	var ordinary = await _open(plain)
	plain.responses.append(_error(409, "stale_revision"))
	await ordinary.commit(fixtures["relay-a"])
	_check(not ordinary.drop_held_submission() and not ordinary.pending().is_empty(), "An ordinary room keeps its held turn for the player to keep")

func _friend_reads_once() -> void:
	var boundary := Boundary.new()
	boundary.identity.player_id = GUEST
	var api := FakeApi.new()
	api.player_id = GUEST
	root.add_child(api)
	var guest_identity := func() -> Dictionary: return {"ready": true, "player_id": GUEST, "epoch": 1}
	var stub := SessionStub.new()
	stub.room_client = HardRoomClient.new(api, guest_identity, MemoryStore.new())
	stub.coordinator = await _open(boundary, _hard(_snapshot(GUEST, 0, false, 9, 1), 1, _last(HOST, 0, "drowned", "b")))
	var run: RefCounted = HardRun.for_room(stub, _path("friend-marks"))
	_check(run.notice("Sam") == PlayerCopy.HARD_FRIEND_NOTICE % ["Sam", 1], "The waiting friend reads who slipped and where")
	var slip := {"recording": fixtures["relay-b"], "checkpoint": fixtures["initial-checkpoint"], "prior": fixtures["relay-a"]}
	var failure := _last(HOST, 0, "drowned", "b")
	failure.slip = slip
	api.answers.append({"ok": true, "status": 200, "data": {"schema_version": 1, "failures": 1, "list": [failure]}})
	var before := HardMode.runs(KEY).size()
	_check(await run.take_in_failures("Sam") == 1, "The friend's slip is kept on this phone too")
	var newest: Dictionary = HardMode.runs(KEY)[-1]
	_check(before > 0 and newest.by == "friend" and newest.friend == "Sam" and newest.reason == "drowned" and newest.slip.prior.recording_hash == fixtures["relay-a"].recording_hash, "It keeps who slipped, how, and the slip with its memory")
	_check(run.notice("Sam").is_empty() and await run.take_in_failures("Sam") == 0 and api.calls.size() == 1, "Once read, the slip is neither noted nor read again")
	stub.coordinator.adopt_snapshot(_hard(_snapshot(GUEST, 0, false, 10, 2), 2, _last(GUEST)))
	_check(run.notice("Sam").is_empty(), "Your own slip is not noted to you")
	api.queue_free()

func _room_full() -> void:
	var stub := SessionStub.new()
	var boundary := Boundary.new()
	stub.coordinator = _coordinator(boundary)
	stub.coordinator.bind_room(ROOM)
	var run: RefCounted = HardRun.for_room(stub, _path("full-marks"))
	_check(not run.active() and not run.over(), "Before a room is read, nothing is hard")
	var adopted: bool = stub.coordinator.adopt_snapshot(_hard(_snapshot(HOST), 6, _last(GUEST), true))
	_check(adopted and run.active() and run.over(), "A room with no space for another run says it is over: " + stub.coordinator.last_code)

func _session_body() -> void:
	var api := FakeApi.new()
	root.add_child(api)
	var session := Session.new(api, _identity, MemoryStore.new())
	session.capabilities = {}
	_check(not session.hard_mode_supported(), "A server that has not said so hosts no hard rooms")
	session.capabilities = {"hard_mode_version": 1.0}
	_check(session.hard_mode_supported(), "A server that says so hosts hard rooms")
	session._owner = HOST
	var body := {"idempotency_key": "x".repeat(36), "level_id": "relay-isles", "level_version": 2, "definition_hash": Canonical.digest(level), "mode": "hard"}
	var index := {"schema_version": 2, "owner_player_id": HOST, "room_ids": [], "standalone_ids": [], "last_room": "", "pending": {"path": "/v2/rooms", "body": body, "request_hash": Canonical.digest({"path": "/v2/rooms", "body": body})}}
	_check(session._valid_index(index), "A kept hard room creation reloads")
	body.mode = "easy"
	index.pending = {"path": "/v2/rooms", "body": body, "request_hash": Canonical.digest({"path": "/v2/rooms", "body": body})}
	_check(not session._valid_index(index), "A kept creation with an unknown mode is refused")
	var headers := RoomsApi.capability_headers(HTTPClient.METHOD_GET, "/v2/capabilities")
	_check("X-AfterYou-Hard-Mode: 1" in headers and "X-AfterYou-Hard-Mode: 1" in RoomsApi.capability_headers(HTTPClient.METHOD_POST, "/v2/rooms/join"), "This build asks about hard rooms and joins them")
	_check(not "X-AfterYou-Hard-Mode: 1" in RoomsApi.capability_headers(HTTPClient.METHOD_GET, "/v2/rooms/" + ROOM), "Polls carry no hard header")
	api.queue_free()
