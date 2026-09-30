extends SceneTree
const Fixture = preload("res://tests/replay_transfer_fixture.gd")
const Transfer = preload("res://services/replay_transfer.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const Session = preload("res://services/relay_online_session.gd")
const Recent = preload("res://tests/test_recent_rooms.gd")
const Memory = Fixture.Memory
const HOST := Fixture.HOST
const GUEST := Fixture.GUEST
const ROOM := Fixture.ROOM
var checks := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()
func _check(okay: bool, message: String) -> void:
	checks += 1
	if not okay: failures += 1; push_error(message)
func _fixture(path: String) -> Dictionary: return Fixture.fixture(path)
func _archive(chapter: String, checkpoint: Dictionary) -> Dictionary: return Fixture.archive(chapter, checkpoint)
func _manifest(archive: Dictionary) -> Dictionary: return Fixture.manifest(archive)

class Photos extends RefCounted:
	var scopes: Array = []
	func list_scopes(_owner: String) -> Dictionary: return {"ok": true, "scopes": scopes.duplicate(true)}

class Api extends Node:
	var player_id := HOST
	var device_token := "synthetic-transfer-session"
	var base_url := "https://synthetic.invalid"
	var busy := false
	var compact := false
	var archive: Dictionary
	var manifest: Dictionary
	var room: Dictionary
	var receipt: Dictionary = {}
	var calls: Array = []
	var acked: Array = [GUEST]
	var fail_lookup := false
	var wrong_receipt := false
	var mutate_endpoint := false
	var lobby_hidden := false
	var compact_lobby := false
	func lobby_room() -> Dictionary:
		if not compact: return room.duplicate(true)
		var summary: Dictionary = manifest.room.duplicate(true)
		summary.merge({"replay_transfer_version": 1, "api_version": 2, "active_role": "complete"})
		return summary
	func envelope() -> Dictionary:
		return {"schema_version": 1, "manifest": manifest.duplicate(true), "acked_player_ids": acked.duplicate() if compact else [], "transferred": compact}
	func request_json(method: int, path: String, body: Dictionary = {}) -> Dictionary:
		calls.append({"method": method, "path": path, "body": body.duplicate(true)})
		if mutate_endpoint:
			mutate_endpoint = false
			base_url = "https://changed.invalid"
		if path == "/v2/capabilities":
			var chapter := Registry.descriptor(Registry.RELAY)
			return {"ok": true, "data": {"api_version": 2, "recording_version": 2, "simulation_version": 2, "mutations_enabled": true, "replay_transfer_version": 1, "validation": "structural_client_replay_required", "chapters": [{"level_id": chapter.level_id, "level_version": chapter.level_version, "definition_hash": chapter.definition_hash, "premium": false}]}}
		if path == "/v2/rooms": return {"ok": true, "data": {"rooms": [] if lobby_hidden or (compact and not compact_lobby) else [lobby_room()]}}
		if "/replay-transfer/operations/" in path:
			if fail_lookup: return {"ok": false, "status": 0, "code": "connection_interrupted"}
			if receipt.is_empty(): return {"ok": false, "status": 404, "code": "operation_not_found"}
			var value := receipt.duplicate(true)
			if wrong_receipt: value.idempotency_key = "wrong-key-".repeat(3)
			return {"ok": true, "data": {"schema_version": 1, "receipt": value, "transfer": envelope()}}
		if path.ends_with("/replay-transfer/ack"):
			acked = [HOST, GUEST]
			compact = true
			return {"ok": true, "data": envelope()}
		if path.ends_with("/replay-transfer/restore"):
			if body.epoch != manifest.epoch or body.archive_hash != manifest.archive_hash or not Canonical.same(body.archive, archive): return {"ok": false, "status": 409, "code": "replay_transfer_changed"}
			manifest.epoch += 1
			compact = false
			acked = []
			return {"ok": true, "data": {"restored": true, "transfer": envelope()}}
		if path.ends_with("/replay-transfer"):
			var result := envelope()
			result["archive"] = null if compact else archive.duplicate(true)
			return {"ok": true, "data": result}
		if compact: return {"ok": false, "status": 410, "code": "replay_transferred"}
		if "/operations/" in path:
			return {"ok": false, "status": 404, "code": "operation_not_found"} if receipt.is_empty() else {"ok": true, "data": {"receipt": receipt.duplicate(true), "room": room.duplicate(true)}}
		if path == "/v2/rooms/" + ROOM: return {"ok": true, "data": room.duplicate(true)}
		if path.ends_with("/fork") or path.ends_with("/turns"): return {"ok": false, "status": 409, "code": "stale_revision"}
		return {"ok": false, "status": 404, "code": "not_found"}

func _snapshot(stored: Dictionary) -> Dictionary:
	var room := stored.duplicate(true)
	var level := Registry.definition(Registry.RELAY)
	room.merge({"api_version": 2, "active_role": "complete", "first_player_id": null, "active_player_id": null, "player_slot": "p0", "stage_id": "", "recording_a": null, "validation": "structural_client_replay_required", "invite_code": "A1".repeat(10)})
	if room.stage_index < 2:
		var stage: Dictionary = level.stages[room.stage_index]
		var first: String = HOST if stage.first_player_slot == "p0" else GUEST
		room.stage_id = stage.id
		room.first_player_id = first
		room.active_role = "b"
		room.active_player_id = GUEST if first == HOST else HOST
	return room

func _setup(origin: Dictionary = {}) -> Dictionary:
	var archive := _archive(Registry.RELAY, _fixture("v2/final-checkpoint"))
	var api := Api.new()
	api.archive = archive
	api.manifest = _manifest(archive)
	api.room = _snapshot(archive.room)
	root.add_child(api)
	var identity := Recent.Identity.new()
	identity.player = HOST
	var journal := Recent.MemoryStore.new()
	journal.values["relay-lobby-v2:" + HOST] = {"schema_version": 2, "owner_player_id": HOST, "room_ids": [ROOM], "standalone_ids": [ROOM], "last_room": ROOM, "pending": {}}
	var session := Session.new(api, identity.current, journal)
	_check(session._ready(), "Owner lobby loaded")
	session.capabilities = {"replay_transfer_version": 1, "mutations_enabled": true}
	session.photo_store = Photos.new()
	session.coordinator = session._ordinary_coordinator()
	_check(session._bind_room(ROOM), "Coordinator bound to the participant")
	_check(session.coordinator.accept_room_snapshot(api.room if origin.is_empty() else origin), "Original full native snapshot accepted")
	var archive_store := Memory.new()
	session._replay_transfer = Transfer.new(session._transfer_transport, identity.current, session._transfer_eligibility, archive_store)
	return {"api": api, "session": session, "identity": identity, "journal": journal, "archive_store": archive_store}

func _close(value: Dictionary) -> void:
	value.session.replay_archive_cache = Callable()
	value.session.invalidate_identity()
	value.api.queue_free()

func _run() -> void:
	await _delivery()
	await _holds()
	await _lobby_pruning()
	await _cold_transferred_lobby()
	await _restore_endpoint_change()
	await _pending_recovery()
	await _restore_before_fork()
	print("REPLAY TRANSFER SESSION: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _delivery() -> void:
	var value := _setup()
	var session: RefCounted = value.session
	var api: Api = value.api
	var adopted := {"count": 0}
	session.replay_archive_cache = func(room: String, entries: Array, manifest: Dictionary):
		adopted.count += 1
		_check(room == ROOM and entries.size() == 2 and value.archive_store.reads >= 2 and manifest.epoch == 1 and api.calls.size() == 1, "Cache adoption follows complete durable archive readback before any ACK")
		return true
	var result: Dictionary = await session.sync_complete_replay(ROOM)
	_check(result.get("ok", false) and result.get("acknowledged", false) and adopted.count == 1 and api.compact, "Both participants' acknowledgements complete transfer")
	var snapshot: Dictionary = session.coordinator.snapshot()
	var before := api.calls.size()
	_check(not await session.coordinator.refresh() and session.coordinator.last_code == "replay_transferred" and Canonical.same(snapshot, session.coordinator.snapshot()), "Ordinary compact refresh retains the real local completed checkpoint")
	_check(api.calls.size() == before + 1 and session.last_room() == ROOM and ROOM in session._index.room_ids, "Read-only compact refresh never restores or drops the lobby link")
	_close(value)

func _holds() -> void:
	for condition: String in ["cache", "disabled", "photo", "redo", "gameplay", "endpoint", "story"]:
		var value := _setup()
		var session: RefCounted = value.session
		var api: Api = value.api
		session.replay_archive_cache = func(_room: String, _entries: Array, _manifest_value: Dictionary): return condition != "cache"
		if condition == "disabled": session.capabilities.replay_transfer_version = 0
		if condition == "photo": session.photo_store.scopes = [{"scope": "turn-photo-v1:" + HOST + ":" + ROOM + ":t0-1-b", "value": {"pending": {"operation": "upload"}, "cleanup": []}}]
		if condition == "redo": value.journal.values["relay-redo-relay-v1:" + HOST + ":" + ROOM] = {"bad": true}
		if condition == "gameplay": session.coordinator.read_only = true
		if condition == "endpoint": api.mutate_endpoint = true
		if condition == "story": session._index.standalone_ids = []
		var result: Dictionary = await session.sync_complete_replay(ROOM)
		_check(not result.get("acknowledged", false) and not api.calls.any(func(call: Dictionary): return call.path.ends_with("/ack")), "No ACK while required boundary fails: " + condition)
		_check(not session._transfer_busy, "Failed or held transfer releases the owned busy flag: " + condition)
		_close(value)

func _lobby_pruning() -> void:
	for condition: String in ["ordinary", "transferred", "other_endpoint"]:
		var value := _setup()
		var session: RefCounted = value.session
		var api: Api = value.api
		if condition != "ordinary":
			session.replay_archive_cache = func(_room: String, _entries: Array, _manifest_value: Dictionary): return true
			_check((await session.sync_complete_replay(ROOM)).get("acknowledged", false), "Lobby retention starts from a durable acknowledged transfer: " + condition)
		var native_scope := "relay-room-v2:" + HOST + ":" + ROOM
		var journal_hash := Canonical.digest(value.journal.values[native_scope])
		var archive_hash := Canonical.digest(value.archive_store.values)
		api.lobby_hidden = true
		if condition == "other_endpoint": api.base_url = "https://changed.invalid"
		api.calls.clear()
		_check(await session.load_lobby(), "An omitted room refresh remains valid: " + condition)
		if condition == "transferred":
			_check(session.room_ids() == [ROOM] and session._index.room_ids == [ROOM] and session._index.standalone_ids == [ROOM] and session.room_summaries()[0].active_role == "complete", "Only the verified current-endpoint transfer retains its completed room link and proof")
		else:
			_check(session.room_ids().is_empty() and session._index.room_ids.is_empty() and session._index.standalone_ids.is_empty(), "List omission prunes membership and standalone proof without current transfer evidence: " + condition)
		_check(session.last_room() == ROOM and Canonical.digest(value.journal.values[native_scope]) == journal_hash and Canonical.digest(value.archive_store.values) == archive_hash, "Pruning preserves the selected recovery pointer, native journal, and any durable archive: " + condition)
		_check(api.calls.size() == 2 and api.calls.all(func(call: Dictionary): return call.method == HTTPClient.METHOD_GET and call.path in ["/v2/capabilities", "/v2/rooms"]), "Lobby pruning adds no room, archive, restore, or mutation request: " + condition)
		_close(value)

func _cold_transferred_lobby() -> void:
	var value := _setup()
	var api: Api = value.api
	value.session.replay_archive_cache = func(_room: String, _entries: Array, _manifest_value: Dictionary): return true
	_check((await value.session.sync_complete_replay(ROOM)).get("acknowledged", false) and api.compact, "Cold lobby begins after durable replay delivery and server compaction")
	var journal := Recent.MemoryStore.new()
	journal.values = value.journal.values.duplicate(true)
	var archive_store := Memory.new()
	archive_store.values = value.archive_store.values.duplicate(true)
	var saved_archive := Canonical.digest(archive_store.values)
	var native_scope := "relay-room-v2:" + HOST + ":" + ROOM
	var saved_journal := Canonical.digest(journal.values[native_scope])
	var saved_snapshot: Dictionary = journal.values[native_scope].snapshot.duplicate(true)
	value.session.replay_archive_cache = Callable()
	value.session.invalidate_identity()
	var identity := Recent.Identity.new()
	identity.player = HOST
	var cold := Session.new(api, identity.current, journal)
	cold.photo_store = Photos.new()
	cold._replay_transfer = Transfer.new(cold._transfer_transport, identity.current, cold._transfer_eligibility, archive_store)
	value.session = cold
	value.identity = identity
	value.journal = journal
	value.archive_store = archive_store
	api.compact_lobby = true
	api.calls.clear()
	var summary := api.lobby_room()
	_check(summary.api_version == 2 and summary.active_role == "complete" and summary.replay_transfer_version == 1 and not ["invite_code", "checkpoint", "recording_a", "turns", "pairs"].any(func(key: String): return summary.has(key)), "Cold list uses only the backend's exact compact room metadata")
	_check(cold._transferred_rooms.is_empty() and await cold.load_lobby(), "A fresh Session discovers the compact room without the former in-memory transfer map")
	_check(cold.room_ids() == [ROOM] and cold._index.standalone_ids == [ROOM] and cold.room_summaries()[0].active_role == "complete" and cold._transferred_rooms.is_empty(), "Authoritative compact membership preserves the completed cold room link and its existing proof")
	_check(api.calls.size() == 2 and api.calls.all(func(call: Dictionary): return call.method == HTTPClient.METHOD_GET and call.path in ["/v2/capabilities", "/v2/rooms"]) and archive_store.reads == 0, "Cold lobby adds no archive reads, native archive validation, or per-room HTTP")
	_check(not await cold.open_room(ROOM) and cold.coordinator.last_code == "replay_transferred" and Canonical.same(cold.coordinator.snapshot(), saved_snapshot), "Explicit cold open receives typed 410 while retaining the genuine saved checkpoint")
	_check(cold.room_ids() == [ROOM] and cold.last_room() == ROOM and api.calls.size() == 3 and api.calls.back().path == "/v2/rooms/" + ROOM and archive_store.reads == 0 and Canonical.digest(journal.values[native_scope]) == saved_journal and Canonical.digest(archive_store.values) == saved_archive, "Read-only cold open preserves the room link, native journal, and archive without restoration")
	api.calls.clear()
	var restored: Dictionary = await cold.restore_complete_replay(ROOM)
	_check(restored.get("ok", false) and not api.compact and api.calls.size() == 3 and api.calls[0].path == "/v2/rooms/" + ROOM and api.calls[1].path == "/v2/rooms/" + ROOM + "/replay-transfer" and api.calls[2].path == "/v2/rooms/" + ROOM + "/replay-transfer/restore", "Explicit cold restore uses the durable archive only after the typed compact response")
	_check(api.calls[2].method == HTTPClient.METHOD_POST and Canonical.same(api.calls[2].body.archive, api.archive) and archive_store.reads > 0 and await cold.coordinator.refresh() and Canonical.same(cold.coordinator.snapshot(), saved_snapshot), "Cold restore submits the exact archive and re-enters through ordinary native snapshot validation")
	_close(value)

func _restore_endpoint_change() -> void:
	var value := _setup()
	var session: RefCounted = value.session
	var api: Api = value.api
	_check((await session._transfer_client().download(ROOM)).get("ok", false), "Endpoint change begins with an exact durable participant archive")
	var saved := Canonical.digest(value.archive_store.values)
	api.compact = true
	api.acked = [HOST, GUEST]
	api.calls.clear()
	api.mutate_endpoint = true
	var result: Dictionary = await session.restore_complete_replay(ROOM)
	_check(not result.get("ok", false) and result.get("code") == "replay_transfer_context_changed", "Endpoint replacement during the first compact-room GET cancels restoration")
	_check(api.calls.size() == 1 and api.calls[0].method == HTTPClient.METHOD_GET and api.calls[0].path == "/v2/rooms/" + ROOM, "A first-GET endpoint change permits no follow-up archive download or restore")
	_check(not session._transfer_busy and Canonical.digest(value.archive_store.values) == saved, "Cancelled restore releases its own busy flag without rewriting the durable archive")
	_close(value)

func _origin() -> Dictionary:
	var final := _fixture("v2/final-checkpoint")
	var room: Dictionary = _archive(Registry.RELAY, final).room
	room.stage_index = 1
	room.revision = 4
	room.checkpoint = Registry.previous_checkpoint(Registry.RELAY, final)
	room.completed_pair_ids = ["p0-0"]
	room.a_turn_id = "t0-1-a"
	room = _snapshot(room)
	room.recording_a = final.proof.a
	return room

func _pending_recovery() -> void:
	for condition: String in ["accepted", "wrong_receipt", "uncertain", "absent"]:
		var value := _setup(_origin())
		var session: RefCounted = value.session
		var api: Api = value.api
		_check((await session._transfer_client().download(ROOM)).get("ok", false), "Participant already has the completed durable archive")
		var body := {"base_revision": 4, "branch": 0, "idempotency_key": "original-turn-request-000000000001", "recording": api.archive.pairs[1].b, "checkpoint": api.archive.room.checkpoint}
		_check(session.coordinator._prepare_pending("turns", body), "Exact final B request is durable before receipt recovery")
		var pending: Dictionary = session.coordinator.pending()
		api.receipt = {"schema_version": 2, "room_id": ROOM, "idempotency_key": body.idempotency_key, "request_hash": pending.request_hash, "operation": "turns", "accepted_revision": 5, "branch": 0, "stage_index": 1, "stage_id": body.recording.stage_id, "turn_id": "t0-1-b", "recording_hash": body.recording.recording_hash, "pair_id": "p0-1", "checkpoint_hash": body.checkpoint.checkpoint_hash}
		api.compact = true
		api.acked = [HOST, GUEST]
		session.capabilities.replay_transfer_version = 0
		api.wrong_receipt = condition == "wrong_receipt"
		api.fail_lookup = condition == "uncertain"
		if condition == "absent": api.receipt = {}
		var result: bool = await session.coordinator.reconcile()
		var restores: Array = api.calls.filter(func(call: Dictionary): return call.path.ends_with("/restore"))
		if condition == "accepted":
			_check(result and session.coordinator.pending().is_empty() and restores.size() == 1 and session.coordinator.last_receipt().idempotency_key == body.idempotency_key, "Exact transferred receipt restores archive then uses unchanged normal receipt validation while ACK flag is disabled")
		elif condition == "absent":
			var posts: Array = api.calls.filter(func(call: Dictionary): return call.path.ends_with("/turns") and call.method == HTTPClient.METHOD_POST)
			_check(not result and restores.size() == 1 and posts.size() == 1 and Canonical.same(posts[0].body, body) and session.coordinator.pending().body.idempotency_key == body.idempotency_key, "Definitive missing receipt permits only the exact original request; stale revision does not rebase")
		else:
			_check(not result and restores.is_empty() and Canonical.same(pending, session.coordinator.pending()), "Uncertain or mismatched transferred receipt neither restores nor changes the original pending operation: " + condition)
		_close(value)

func _restore_before_fork() -> void:
	var value := _setup()
	var session: RefCounted = value.session
	var api: Api = value.api
	_check((await session._transfer_client().download(ROOM)).get("ok", false), "Fork restore has an existing verified local archive")
	api.compact = true
	api.acked = [HOST, GUEST]
	session.capabilities.replay_transfer_version = 0
	_check(not await session.coordinator.fork(0), "Synthetic server's ordinary stale rejection remains authoritative")
	var restore_index := -1
	var fork_index := -1
	for index in range(api.calls.size()):
		if api.calls[index].path.ends_with("/restore"): restore_index = index
		if api.calls[index].path.ends_with("/fork"): fork_index = index
	_check(restore_index >= 0 and fork_index > restore_index and session.coordinator.pending().body.base_revision == 5, "Explicit new fork restores exact coordinates before creating its request against the genuine normal snapshot")
	_close(value)
