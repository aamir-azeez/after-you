extends SceneTree
## Play my turn again (the coordinator's replace) and start over (the redo
## client's over_* actions) against a version 2 server stub.
const Session = preload("res://services/relay_online_session.gd")
const Client = preload("res://services/redo_client.gd")
const Recent = preload("res://tests/test_recent_rooms.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const RoomRunReset = preload("res://services/room_run_reset.gd")
const HOST := Recent.HOST
const GUEST := Recent.GUEST
const ROOM := Recent.ROOM

class Api:
	extends Node
	var player_id := HOST
	var device_token := "synthetic-self-redo"
	var base_url := "https://synthetic.invalid"
	var rooms: Dictionary = {}
	var replace_open := true
	var start_over: Variant = null
	var run_from := 0
	var seen := false
	var calls: Array = []
	var receipts: Dictionary = {}
	func request_json(method: int, path: String, body: Dictionary = {}, _still: Callable = Callable()) -> Dictionary:
		calls.append({"path": path, "method": method, "body": body.duplicate(true)})
		var room: Dictionary = rooms.get(ROOM, {})
		if path == "/v2/capabilities":
			var chapter := Registry.descriptor(Registry.RELAY)
			return _ok({"api_version": 2, "recording_version": 2, "simulation_version": 2, "mutations_enabled": true, "poll_redo_version": 1, "redo_extras_version": 1, "validation": "structural_client_replay_required",
				"chapters": [{"level_id": chapter.level_id, "level_version": chapter.level_version, "definition_hash": chapter.definition_hash, "premium": false}]})
		if path == "/v2/rooms": return _ok({"rooms": rooms.values()})
		if path.get_file() in rooms: return _ok(room)
		if path.ends_with("/redo") and method == HTTPClient.METHOD_GET:
			var source := Client.source_for("relay", room)
			return _ok({"schema_version": 2, "source": null if source.is_empty() else source, "request": null, "start_over": start_over, "replace_open": replace_open, "run_from": run_from})
		if path.ends_with("/turns"):
			if seen: return {"ok": false, "status": 409, "code": "turn_already_seen"}
			if body.get("replaces") != room.recording_a.recording_hash or int(body.base_revision) != int(room.revision): return {"ok": false, "status": 409, "code": "redo_source_changed"}
			room.revision += 1
			room.branch += 1
			room.a_turn_id = "t%d-0-a" % int(room.branch)
			room.recording_a = body.recording.duplicate(true)
			return _ok(_receipt(room, body, "turns", room.a_turn_id, body.recording.recording_hash))
		if path.ends_with("/fork"):
			if start_over == null or body.get("redo_request_id") != start_over.request_id or int(body.stage_index) != 0: return {"ok": false, "status": 409, "code": "redo_request_missing"}
			room.revision += 1
			room.branch += 1
			room.active_role = "a"
			room.active_player_id = HOST
			room.a_turn_id = null
			room.recording_a = null
			start_over = null
			run_from = int(room.branch)
			return _ok(_receipt(room, body, "fork", null, null))
		return {"ok": false, "status": 404, "code": "not_found"}
	func _receipt(room: Dictionary, body: Dictionary, operation: String, turn_id: Variant, recording_hash: Variant) -> Dictionary:
		var hashed := body.duplicate(true)
		hashed.operation = operation
		return {"room": room.duplicate(true), "receipt": {"schema_version": 2, "room_id": ROOM, "idempotency_key": body.idempotency_key, "request_hash": Canonical.digest(hashed), "operation": operation,
			"accepted_revision": room.revision, "branch": room.branch, "stage_index": 0, "stage_id": room.stage_id, "checkpoint_hash": room.checkpoint.checkpoint_hash, "turn_id": turn_id, "recording_hash": recording_hash, "pair_id": null}}
	func _ok(value: Dictionary) -> Dictionary: return {"ok": true, "data": value.duplicate(true)}

var checks := 0
var failures := 0
func _initialize() -> void: _run.call_deferred()
func _check(value: bool, label: String) -> bool:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
	return value

func _room() -> Dictionary:
	var level := Registry.definition(Registry.RELAY)
	var chapter := Registry.descriptor(Registry.RELAY)
	return {"api_version": 2, "schema_version": 2, "room_id": ROOM, "revision": 2, "branch": 0, "stage_index": 0, "level_id": chapter.level_id, "level_version": chapter.level_version, "definition_hash": chapter.definition_hash, "host_id": HOST, "guest_id": GUEST,
		"checkpoint": JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/v2/initial-checkpoint.json")), "a_turn_id": "t0-0-a", "completed_pair_ids": [], "invite_expires_at": "2026-09-28T00:00:00Z", "created_at": "2026-09-21T00:00:00Z", "updated_at": "2026-09-27T00:00:00Z",
		"active_role": "b", "first_player_id": HOST, "active_player_id": GUEST, "player_slot": "p0", "invite_code": "A1".repeat(10), "stage_id": level.stages[0].id,
		"recording_a": JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/v2/relay-a.json")), "validation": "structural_client_replay_required"}

func _run() -> void:
	var api := Api.new()
	root.add_child(api)
	api.rooms = {ROOM: _room()}
	var identity := Recent.Identity.new()
	identity.player = HOST
	var session := Session.new(api, identity.current, Recent.MemoryStore.new())
	if not _check(await session.load_lobby() and await session.open_room(ROOM) and session.redo_extras_supported(), "A version 2 server opens the room with redo extras"):
		push_error(session.last_error)
		quit(1)
		return
	var coordinator: RefCounted = session.coordinator
	var client: RefCounted = session.redo_client()
	_check(client.bind_room("relay", coordinator.snapshot()) and await client.refresh() and client.replace_open(), "The first player reads Play my turn again as open")
	_check(not coordinator.my_turn(), "The saved turn waits for the friend")
	# Leaving without saving keeps the saved turn.
	_check(coordinator.begin_replace() and coordinator.replacing() and coordinator.my_turn() and coordinator.role() == "a" and coordinator.prior_recording().is_empty(), "Playing again shows the room from before the saved turn")
	coordinator.end_replace()
	_check(not coordinator.replacing() and not coordinator.my_turn() and coordinator.snapshot().a_turn_id == "t0-0-a", "Keep it as it is goes back to the saved turn")
	# Saving replaces it in one request, and the receipt names the new branch.
	var old_hash: String = coordinator.snapshot().recording_a.recording_hash
	var recording: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/v2/relay-a.json"))
	_check(coordinator.begin_replace(), "Play my turn again starts")
	var saved: bool = await coordinator.commit(recording)
	if not _check(saved, "The replacement saves"): push_error(coordinator.last_error)
	var sent: Dictionary = api.calls.filter(func(call: Dictionary) -> bool: return call.path.ends_with("/turns")).back().body
	_check(sent.get("replaces") == old_hash and int(sent.base_revision) == 2 and int(sent.branch) == 0, "The turn names the saved turn it replaces, against the room the friend has not seen")
	_check(int(coordinator.snapshot().branch) == 1 and coordinator.snapshot().a_turn_id == "t1-0-a" and not coordinator.replacing() and coordinator.pending().is_empty(), "The room moves to the new branch with the new first turn")
	# Once the friend has it, the server refuses and the turn is held, never sent twice.
	api.seen = true
	_check(coordinator.begin_replace(), "A second replacement can start while the poll still says open")
	_check(not await coordinator.commit(recording) and coordinator.last_code == "turn_already_seen" and not coordinator.replacing(), "A refused replacement ends Play my turn again")
	_check(coordinator.archive_held_submission() and coordinator.snapshot().a_turn_id == "t1-0-a", "The refused turn is kept aside and the saved one stays")
	# Start over: the friend asked; agreeing forks back to the first stage.
	var asked := Client.start_over_source(api.rooms[ROOM], GUEST)
	api.start_over = {"request_id": Canonical.digest(asked), "source": asked, "status": "pending"}
	api.replace_open = false
	_check(await coordinator.refresh() and client.bind_room("relay", coordinator.snapshot()) and await client.refresh(), "The room and its redo state read again")
	_check(client.can_answer_start_over() and client.start_over_role() == "friend" and not client.can_ask_start_over(), "The friend's start over waits for this player's answer")
	_check(not Client.valid_view({"schema_version": 2, "source": Client.source_for("relay", api.rooms[ROOM]), "request": null, "start_over": {"request_id": Canonical.digest(asked), "source": asked.merged({"revision": 99}, true), "status": "pending"}, "replace_open": false, "run_from": 0}, Client.source_for("relay", api.rooms[ROOM]), api.rooms[ROOM]), "A start over for another room position is refused")
	_check(await client.accept_start_over() and client.accepted and client.pending().is_empty(), "Agreeing forks the room back")
	var fork: Dictionary = api.calls.filter(func(call: Dictionary) -> bool: return call.path.ends_with("/fork")).back().body
	_check(int(fork.stage_index) == 0 and fork.redo_request_id == Canonical.digest(asked), "The fork goes to the first stage with the request's id")
	_check(not coordinator.held_drafts().is_empty(), "The refused turn was kept aside before the start over")
	_check(client.take_run_reset().is_empty(), "Nothing has been reset before the room is read again")
	_check(await coordinator.refresh() and client.bind_room("relay", coordinator.snapshot()) and await client.refresh() and client.take_run_reset() == ROOM and client.take_run_reset().is_empty(), "The next read names the new run once, as it would for a phone closed when the friend agreed")
	var heard: Array = []
	var listener := func(owner: String, room_id: String) -> void: heard.append(owner + ":" + room_id)
	RoomRunReset.shared().room_reset.connect(listener)
	_check(session.forget_room_run(ROOM) and coordinator.held_drafts().is_empty() and coordinator.last_receipt().is_empty() and heard == [HOST + ":" + ROOM], "The old run's copies on this phone go with it, and every store of the room hears it")
	RoomRunReset.shared().room_reset.disconnect(listener)
	api.queue_free()
	print("self redo: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
