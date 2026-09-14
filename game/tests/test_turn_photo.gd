extends SceneTree
## Synthetic bytes exercise controller transport/integrity, not JPEG decoding.
## Native sanitization and real Worker decoder tests are separate acceptance.
const Controller = preload("res://services/turn_photo_controller.gd")
const LocalAdapter = preload("res://services/turn_photo_local.gd")
const DiskStore = preload("res://services/turn_photo_store.gd")
const Catalog = preload("res://core/v2/stage_catalog.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const OWNER := "HHHHHHHHHHHHHHHHHHHHHH"
const GUEST := "GGGGGGGGGGGGGGGGGGGGGG"
const ROOM := "40173cc9d5bee436613f7a"
const GAME_KEY := "accepted-gameplay-123"
const RECORDING := "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
const PHOTO_ID := "11111111111111111111111111111111"

class Store:
	extends RefCounted
	var values: Dictionary = {}
	var fail := false
	var fail_load := false
	var writes := 0
	func load_scope(scope: String) -> Dictionary:
		return {"ok": not fail_load, "found": values.has(scope), "value": values.get(scope, {}).duplicate(true)}
	func save_scope(scope: String, value: Dictionary) -> Dictionary:
		if fail:
			return {"ok": false}
		writes += 1
		values[scope] = JSON.parse_string(JSON.stringify(value))
		return {"ok": true}

class Identity:
	extends RefCounted
	var player := OWNER
	var epoch := 1
	var ready := true
	func current() -> Dictionary:
		return {"ready": ready, "player_id": player, "epoch": epoch}

class Local:
	extends RefCounted
	signal release
	var calls: Array = []
	var hold := false
	var invalid_bytes := false
	var fail_discard := false
	var bytes := "synthetic-transport-only".to_utf8_buffer()
	func metadata(id: String = PHOTO_ID) -> Dictionary:
		return {"status": "kept", "photo_id": id, "mime": "image/jpeg", "width": 32, "height": 24, "byte_count": bytes.size(), "sha256": Controller._digest(bytes), "metadata_removed": true, "uploaded": false}
	func request(operation: String, id: String) -> Dictionary:
		calls.append({"operation": operation, "id": id})
		if hold:
			hold = false
			await release
		if operation == "discard":
			return {"ok": not fail_discard, "discarded": not fail_discard}
		return {"ok": true, "metadata": metadata(id), "bytes": "changed".to_utf8_buffer() if invalid_bytes else bytes.duplicate()}

class Server:
	extends RefCounted
	signal release
	var calls: Array = []
	var photo: Variant = null
	var encoded: Variant = null
	var receipts: Dictionary = {}
	var mutation_count := 0
	var drop := false
	var drop_before := false
	var hold := false
	var fail_status := 0
	var fail_code := ""
	var corrupt_receipt := false
	var unknown_catalog := false
	var fork_receipt := false
	var stale := false
	var after_mutation: Callable
	func request(request: Dictionary) -> Dictionary:
		calls.append(request.duplicate(true))
		if hold:
			hold = false
			await release
		if fail_status != 0:
			return {"ok": false, "status": fail_status, "code": fail_code}
		var path: String = request.path
		if path.contains("/operations/"):
			var role := "a" if request.owner_player_id == OWNER else "b"
			var turn := "t0-0-" + role
			var receipt := {"schema_version": 2, "room_id": ROOM, "idempotency_key": GAME_KEY, "request_hash": RECORDING, "operation": "fork" if fork_receipt else "turns", "accepted_revision": 2, "branch": 0, "stage_index": 0, "stage_id": "relay", "turn_id": turn, "recording_hash": RECORDING, "pair_id": "p0-0" if role == "b" else null, "checkpoint_hash": RECORDING}
			var room := {"schema_version": 2, "api_version": 2, "room_id": ROOM, "level_id": "relay-isles", "level_version": 2, "definition_hash": RECORDING if unknown_catalog else Canonical.digest(Catalog.relay_isles()), "revision": 5, "host_id": OWNER, "guest_id": GUEST}
			return _ok({"receipt": receipt, "room": room})
		if path.contains("/photo-operations/"):
			var key: String = path.get_slice("/photo-operations/", 1)
			if not receipts.has(key):
				return {"ok": false, "status": 404, "code": "photo_operation_not_found"}
			return _ok({"receipt": receipts[key].duplicate(true), "photo": photo})
		if request.method == HTTPClient.METHOD_GET:
			return _ok({"photo": photo, "jpeg_base64": encoded})
		if drop_before:
			drop_before = false
			return {"ok": false, "status": 0, "code": "connection_interrupted"}
		if stale:
			return {"ok": false, "status": 409, "code": "stale_photo_revision"}
		var body: Dictionary = request.body
		var operation := "photo_upload" if request.method == HTTPClient.METHOD_POST else "photo_delete"
		var turn: String = path.get_slice("/photos/", 1)
		var material := body.duplicate(true)
		material.merge({"operation": operation, "turn_id": turn})
		var digest: String = Canonical.digest(material)
		if receipts.has(body.idempotency_key):
			if receipts[body.idempotency_key].request_hash != digest:
				return {"ok": false, "status": 409, "code": "idempotency_key_reused"}
			return _ok({"receipt": receipts[body.idempotency_key], "photo": photo})
		var expected: int = int(photo.photo_revision) if photo is Dictionary else 0
		var expected_hash: Variant = photo.sha256 if photo is Dictionary else null
		if body.expected_photo_revision != expected or body.expected_photo_hash != expected_hash:
			return {"ok": false, "status": 409, "code": "stale_photo_revision"}
		mutation_count += 1
		encoded = body.get("jpeg_base64")
		var hash: Variant = body.get("sha256")
		photo = {"schema_version": 1, "turn_id": turn, "owner_player_id": request.owner_player_id, "recording_hash": RECORDING, "photo_revision": expected + 1, "sha256": hash, "width": 32 if hash != null else null, "height": 24 if hash != null else null, "byte_length": Marshalls.base64_to_raw(encoded).size() if encoded != null else 0, "updated_at": "2026-09-14T00:00:00.000Z"}
		var receipt := {"schema_version": 1, "room_id": ROOM, "idempotency_key": body.idempotency_key, "request_hash": digest, "operation": operation, "turn_id": turn, "recording_hash": RECORDING, "photo_revision": expected + 1, "photo_hash": hash}
		receipts[body.idempotency_key] = receipt.duplicate(true)
		if after_mutation.is_valid():
			after_mutation.call()
		if drop:
			drop = false
			return {"ok": false, "status": 0, "code": "connection_interrupted"}
		if corrupt_receipt:
			receipt.recording_hash = "b".repeat(64)
		return _ok({"receipt": receipt, "photo": photo})
	func _ok(data: Dictionary) -> Dictionary:
		return {"ok": true, "status": 200, "data": JSON.parse_string(JSON.stringify(data))}

class FakeCapture:
	extends Node
	signal bytes_ready(id: String, metadata: Dictionary, bytes: PackedByteArray)
	signal completed(id: String, operation: String, acknowledgement: Dictionary)
	signal failed(id: String, operation: String, code: String)
	var sequence := 0
	var quiet := false
	var last_id := ""
	func read_photo(_photo: String) -> String:
		sequence += 1
		last_id = "native-" + str(sequence)
		if not quiet:
			bytes_ready.emit(last_id, {"synthetic": true}, PackedByteArray([1, 2]))
		return last_id
	func discard_photo(_photo: String) -> String:
		sequence += 1
		last_id = "native-" + str(sequence)
		completed.emit(last_id, "discard", {"discarded": true})
		return last_id

var checks := 0
var failures := 0
var keys := 0
var async_result: Variant = null

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await _normal_and_retry()
	await _errors_and_lifecycle()
	await _local_adapter()
	_disk_scopes()
	print("After You optional turn photo: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _key() -> String:
	keys += 1
	return "photo-request-%08d" % keys

func _controller(server: Server, store: Store, identity: Identity, local: Local) -> RefCounted:
	return Controller.new(server.request, store.load_scope, store.save_scope, identity.current, local.request, _key)

func _normal_and_retry() -> void:
	var server := Server.new()
	var store := Store.new()
	var identity := Identity.new()
	var local := Local.new()
	var c: RefCounted = _controller(server, store, identity, local)
	_check(server.calls.is_empty(), "constructor does not dispatch or capture")
	_check(await c.open_owned_turn(ROOM, GAME_KEY), "accepted caller receipt opens immutable turn after room advances")
	_check(c.target().turn_id == "t0-0-a" and c.target().role == "a", "target binds branch stage role and hash")
	_check(c.choose_local(local.metadata(), c.selection_context()), "selection persisted without reading or upload")
	_check(local.calls.is_empty() and server.mutation_count == 0, "selection has no network mutation")
	server.drop = true
	_check(not await c.upload_selected(), "lost upload acknowledgement reported uncertain")
	_check(server.mutation_count == 1 and not c.pending().is_empty(), "accepted request and exact local pending retained")
	var saved_scope: String = store.values.keys()[0]
	var exact: Dictionary = store.values[saved_scope].pending.duplicate(true)
	_check(not c.pending().has("body") and not c.pending().has("jpeg_base64"), "status accessor excludes image payload")
	_check(not c.choose_local(local.metadata("2".repeat(32)), c.selection_context()), "pending prevents changing its selected file")
	c.invalidate_identity()
	_check(c.image_bytes().is_empty() and c.target().is_empty(), "invalidation clears exposed cache/context")
	c = _controller(server, store, identity, local)
	_check(await c.open_owned_turn(ROOM, GAME_KEY), "restart opens same immutable pending scope")
	_check(store.values[saved_scope].pending == exact, "opening cannot rewrite pending bytes or key")
	_check(await c.reconcile() and server.mutation_count == 1, "receipt reconciliation does not upload twice")
	_check(c.pending().is_empty() and c.cleanup_count() == 1 and c.selection().is_empty(), "confirmed upload clears selection and queues exact local cleanup")
	_check(await c.refresh_photo() and c.image_bytes() == local.bytes, "member read verifies exact hash and length")
	local.fail_discard = true
	_check(not await c.cleanup_local() and c.cleanup_count() == 1, "failed local discard retained for retry")
	local.fail_discard = false
	_check(await c.cleanup_local() and c.cleanup_count() == 0, "local discard confirmation clears cleanup queue")
	_check(await c.delete_photo() and server.photo.sha256 == null and c.image_bytes().is_empty(), "explicit deletion creates tombstone and clears pixels")
	_check(c.choose_local(local.metadata(), c.selection_context()), "new explicit upload after deletion allowed")
	_check(await c.upload_selected() and server.photo.photo_revision == 3, "replacement uses tombstone revision instead of resetting zero")
	var shared: Dictionary = await c.read_shared(ROOM, "t0-0-a", RECORDING)
	_check(shared.get("bytes") == local.bytes, "shared read returns verified ephemeral bytes")
	_check((await c.read_shared(ROOM, "t0-0-a", "b".repeat(64))).is_empty(), "shared read rejects different recording hash")
	server.photo.photo_revision += 1
	server.photo.sha256 = "d".repeat(64)
	_check(not await c.refresh_photo(), "read rejects changed checksum against bytes")
	# Exact retry after no receipt reuses the body; no available cache is needed.
	var next := Server.new()
	var fresh := Store.new()
	c = _controller(next, fresh, identity, local)
	_check(await c.open_owned_turn(ROOM, GAME_KEY) and c.choose_local(local.metadata(), c.selection_context()), "second independent photo context prepared")
	next.fail_status = 503
	next.fail_code = "v2_mutations_disabled"
	_check(not await c.upload_selected() and c.pending().is_empty(), "failed revision read never stages or uploads")
	next.fail_status = 0
	next.corrupt_receipt = true
	_check(not await c.upload_selected() and not c.pending().is_empty(), "wrong receipt cannot clear accepted pending")
	next.corrupt_receipt = false
	# Newer current metadata beside an old immutable receipt must not invalidate it.
	next.photo.photo_revision += 1
	next.photo.sha256 = "c".repeat(64)
	_check(await c.reconcile() and c.photo_metadata().sha256 == "c".repeat(64) and c.image_bytes().is_empty(), "old receipt accepts newer current photo without displaying stale pixels")
	_check(c.pending().is_empty(), "old successful receipt still unlocks optional editing")
	var interrupted := Server.new()
	var interrupted_store := Store.new()
	c = _controller(interrupted, interrupted_store, identity, local)
	_check(await c.open_owned_turn(ROOM, GAME_KEY) and c.choose_local(local.metadata(), c.selection_context()), "unaccepted request fixture prepared")
	interrupted.drop_before = true
	_check(not await c.upload_selected() and interrupted.mutation_count == 0, "lost request before acceptance remains pending")
	var first_post: Dictionary = interrupted.calls[-1].duplicate(true)
	var local_reads := local.calls.size()
	local.invalid_bytes = true
	_check(await c.reconcile() and interrupted.mutation_count == 1, "missing operation receipt retries saved bytes without native cache")
	_check(interrupted.calls[-1].body == first_post.body and local.calls.size() == local_reads, "retry keeps exact key revision hash and image")
	local.invalid_bytes = false

func _errors_and_lifecycle() -> void:
	var server := Server.new()
	var store := Store.new()
	var identity := Identity.new()
	var local := Local.new()
	var c: RefCounted = _controller(server, store, identity, local)
	server.unknown_catalog = true
	_check(not await c.open_owned_turn(ROOM, GAME_KEY), "unsupported catalog held")
	server.unknown_catalog = false
	server.fork_receipt = true
	_check(not await c.open_owned_turn(ROOM, GAME_KEY), "fork receipt cannot grant photo ownership")
	server.fork_receipt = false
	_check(await c.open_owned_turn(ROOM, GAME_KEY), "valid receipt recovers from unsupported response")
	var old_capture_context: Dictionary = c.selection_context()
	_check(await c.open_owned_turn(ROOM, GAME_KEY), "explicit same-turn reread rotates capture context")
	_check(not c.choose_local(local.metadata(), old_capture_context), "late capture from previous scene cannot attach to reopened turn")
	store.fail = true
	_check(not c.choose_local(local.metadata(), c.selection_context()) and c.selection().is_empty(), "selection write failure cannot expose unsaved file")
	store.fail = false
	_check(c.choose_local(local.metadata(), c.selection_context()), "selection recovered")
	local.invalid_bytes = true
	_check(not await c.upload_selected() and server.mutation_count == 0, "local bytes/metadata mismatch never uploads")
	local.invalid_bytes = false
	store.fail = true
	_check(not await c.upload_selected() and server.mutation_count == 0, "pending write must succeed before POST")
	store.fail = false
	server.stale = true
	_check(not await c.upload_selected() and c.pending().held, "CAS conflict remains explicit rejected pending")
	_check(c.abandon_rejected_request() and c.pending().is_empty(), "only definitive rejection may be abandoned")
	server.stale = false
	server.after_mutation = func() -> void: store.fail = true
	_check(not await c.upload_selected() and server.mutation_count == 1 and not c.pending().is_empty(), "local acknowledgement write failure retains exact accepted request")
	_check(not c.abandon_rejected_request(), "uncertain acknowledgement cannot be abandoned")
	store.fail = false
	server.after_mutation = Callable()
	_check(await c.reconcile(), "receipt can repair failed local acknowledgement write")
	var scope: String = store.values.keys()[0]
	store.values[scope].schema_version = 999
	c = _controller(server, store, identity, local)
	_check(not await c.open_owned_turn(ROOM, GAME_KEY) and c.read_only, "unknown saved journal held")
	_check(not c.choose_local(local.metadata(), c.selection_context()) and store.values[scope].schema_version == 999, "unknown journal never overwritten by repeated action")
	store.values.clear()
	_check(await c.open_owned_turn(ROOM, GAME_KEY), "explicit reread recovers restored journal")
	_check(c.choose_local(local.metadata(), c.selection_context()), "local selection before identity race")
	local.hold = true
	async_result = null
	_await_upload(c)
	await process_frame
	_check(c.busy(), "upload local byte read in flight")
	identity.epoch += 1
	c.invalidate_identity()
	local.release.emit()
	await process_frame
	_check(async_result == false and c.target().is_empty() and server.mutation_count == 1, "late local bytes after recovery never upload")
	_check(await c.open_owned_turn(ROOM, GAME_KEY), "same owner new epoch can explicitly reopen")
	server.hold = true
	async_result = null
	_await_refresh(c)
	await process_frame
	identity.player = GUEST
	identity.epoch += 1
	c.invalidate_identity()
	server.release.emit()
	await process_frame
	_check(async_result == false and c.image_bytes().is_empty(), "late member read after account switch cannot revive pixels")
	_check(await c.open_owned_turn(ROOM, GAME_KEY) and c.target().turn_id == "t0-0-b", "guest accepted role has independent owner/turn scope")
	_check(c.selection().is_empty() and store.values.size() == 1, "new owner does not load prior owner selection")
	server.fail_status = 404
	server.fail_code = "room_not_found"
	_check(not await c.refresh_photo() and c.image_bytes().is_empty(), "deleted or nonmember room read clears cache")
	server.fail_status = 401
	_check(not await c.refresh_photo() and c.target().is_empty(), "authentication rejection invalidates context")

func _await_upload(c: RefCounted) -> void:
	async_result = await c.upload_selected()

func _await_refresh(c: RefCounted) -> void:
	async_result = await c.refresh_photo()

func _await_local(local: Node) -> void:
	async_result = await local.request("read", PHOTO_ID)

func _local_adapter() -> void:
	var wrapper := FakeCapture.new()
	root.add_child(wrapper)
	var adapter := LocalAdapter.new(wrapper)
	root.add_child(adapter)
	var result: Dictionary = await adapter.request("read", PHOTO_ID)
	_check(result.get("bytes") == PackedByteArray([1, 2]), "local adapter accepts synchronous callback after returned request ID")
	_check((await adapter.request("discard", PHOTO_ID)).get("discarded"), "local adapter correlates discard acknowledgement")
	wrapper.quiet = true
	async_result = null
	_await_local(adapter)
	await process_frame
	var id := wrapper.last_id
	wrapper.completed.emit(id, "discard", {"discarded": true})
	wrapper.bytes_ready.emit("wrong-id", {}, PackedByteArray([7]))
	await process_frame
	_check(async_result == null, "mismatched local operation/request callbacks ignored")
	adapter.invalidate()
	await process_frame
	_check(async_result is Dictionary and not async_result.ok, "local adapter invalidation unblocks awaiting request")
	wrapper.bytes_ready.emit(id, {}, PackedByteArray([7]))
	await process_frame
	_check(not async_result.ok, "late old local callback cannot revive cancelled bytes")
	adapter.queue_free()
	wrapper.queue_free()
	await process_frame

func _disk_scopes() -> void:
	var folder := "user://photo-test-" + Crypto.new().generate_random_bytes(8).hex_encode()
	var store := DiskStore.new(folder)
	var first := "turn-photo-v1:" + OWNER + ":" + ROOM + ":t0-0-a"
	var second := "turn-photo-v1:" + GUEST + ":" + ROOM + ":t0-0-b"
	_check(store.save_scope(first, {"synthetic": 1}).get("ok"), "disk writes independent photo generation")
	_check(store.save_scope(first, {"synthetic": 2}).get("ok"), "disk keeps recoverable previous generation")
	_check(store.save_scope(second, {"synthetic": 3}).get("ok"), "disk creates other owner isolated scope")
	_check(not store.save_scope("../../journey", {}).get("ok"), "disk rejects arbitrary path scope")
	_check(store.erase_owner(OWNER).get("ok"), "explicit account removal erases all owner generations")
	_check(not store.load_scope(first).get("found") and store.load_scope(second).get("value").synthetic == 3, "owner erasure cannot remove another identity save")
	_check(store.erase_owner(GUEST).get("ok"), "synthetic second owner cleanup")
	for owner: String in [OWNER, GUEST]:
		DirAccess.remove_absolute(folder.path_join(owner.sha256_text()))
	DirAccess.remove_absolute(folder)

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label) # Fixed labels only: no requests/images/credentials.
