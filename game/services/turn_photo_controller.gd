class_name TurnPhotoController
extends RefCounted
## Optional media only. No gameplay coordinator/save or credential access.
## transport uses RelayOnlineSession.transport's owner/epoch envelope. local_io
## is TurnPhotoLocal.request; load/save are atomic owner/room/turn scoped stores.
## UI must call invalidate_identity before recovery/deletion/logout. No startup
## upload, automatic capture, or implicit retries; each mutation is explicit.

const Canonical = preload("res://core/v2/canonical.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Catalog = preload("res://core/v2/stage_catalog.gd")
const Capture = preload("res://services/optional_photo_capture.gd")
const MAX_BYTES := 160 * 1024
const MAX_STATE := 256 * 1024
const META_KEYS := ["schema_version", "turn_id", "owner_player_id", "recording_hash", "photo_revision", "sha256", "width", "height", "byte_length", "updated_at"]
const RECEIPT_KEYS := ["schema_version", "room_id", "idempotency_key", "request_hash", "operation", "turn_id", "recording_hash", "photo_revision", "photo_hash"]
const TARGET_KEYS := ["room_id", "turn_id", "recording_hash", "owner_player_id", "branch", "stage_index", "stage_id", "role", "gameplay_key"]
const STATE_KEYS := ["schema_version", "target", "selection", "pending", "cleanup", "last_receipt"]
var last_code := ""
var last_error := ""
var read_only := false
var _transport: Callable
var _load: Callable
var _save: Callable
var _identity: Callable
var _local: Callable
var _keys: Callable
var _library: RefCounted
var _owner := ""
var _epoch := -1
var _generation := 0
var _busy := false
var _scope := ""
var _state: Dictionary = {}
var _photo: Variant = null
var _image := PackedByteArray()
var _observed := false
var _open_phase := "input"
var _open_http_status := 0

func last_open_diagnostic() -> Dictionary:
	# Fixed phase, bounded status and the controller's existing allowlisted code.
	# No request, identity, recording, local filename or image data is exposed.
	return {"phase": _open_phase, "http_status": _open_http_status, "code": last_code}

func _init(transport: Callable, load_store: Callable, save_store: Callable, identity_owner: Callable, local_io: Callable, key_factory: Callable = Callable(), photo_library: RefCounted = null) -> void:
	_transport = transport
	_load = load_store
	_save = save_store
	_identity = identity_owner
	_local = local_io
	_keys = key_factory
	_library = photo_library

func keep_selected_bytes(metadata: Dictionary, bytes: PackedByteArray) -> bool:
	# Keeping is local even if the player never presses Share. Do not retire a
	# native selection until its exact pixels and provenance are durable here.
	if not _guard() or not Canonical.same(metadata, selection()):
		return false
	if _library == null:
		return true
	var result: Dictionary = _library.store_local(_owner, target(), metadata, bytes)
	return result.get("ok", false) and result.get("durable", false)

func invalidate_identity() -> void:
	_generation += 1
	_busy = false
	_owner = ""
	_epoch = -1
	_scope = ""
	_state.clear()
	_photo = null
	_image = PackedByteArray()
	_observed = false
	read_only = false
	_fail("identity_changed")

func busy() -> bool:
	return _busy

func target() -> Dictionary:
	return _state.get("target", {}).duplicate(true) if _guard() else {}

func pending() -> Dictionary:
	# No image/base64 leaves this status accessor.
	if not _guard() or _state.pending.is_empty():
		return {}
	return {"operation": _state.pending.operation, "idempotency_key": _state.pending.body.idempotency_key, "held": _state.pending.held}

func selection() -> Dictionary:
	return _state.get("selection", {}).duplicate(true) if _guard() else {}

func selection_context() -> Dictionary:
	# Capture this token before opening the camera. Never substitute the current
	# context when an old camera activity returns after navigation or recovery.
	return {"target": target(), "generation": _generation, "owner": _owner, "epoch": _epoch} if _guard() else {}

func photo_metadata() -> Dictionary:
	return _photo.duplicate(true) if _guard() and _photo is Dictionary else {}

func image_bytes() -> PackedByteArray:
	return _image.duplicate() if _guard() else PackedByteArray()

func cleanup_count() -> int:
	return _state.get("cleanup", []).size() if _guard() else 0

func open_owned_turn(room_id: String, gameplay_key: String) -> bool:
	_open_phase = "input"
	_open_http_status = 0
	if not _id(room_id) or not _key(gameplay_key):
		return _fail("invalid_target")
	_open_phase = "identity"
	var ticket := _begin(true)
	if ticket < 0:
		return false
	_generation += 1
	ticket = _generation
	# Switching optional media never touches pending gameplay. Unresolved photo
	# requests remain in their original disk scope and can be reopened explicitly.
	_state = {}
	_scope = ""
	_photo = null
	_image = PackedByteArray()
	_observed = false
	read_only = false
	_open_phase = "receipt"
	var response := await _net(HTTPClient.METHOD_GET, "/v2/rooms/" + room_id + "/operations/" + gameplay_key, {}, ticket)
	if not _same(ticket):
		return false
	_open_http_status = clampi(int(response.get("status", 0)), 0, 599)
	if not response.get("ok", false):
		return _finish(ticket, _response_error(response))
	var accepted: Dictionary = _accepted_target(response.get("data"), room_id, gameplay_key)
	if accepted.is_empty():
		return _finish(ticket, _fail("unsupported_target"))
	_open_phase = "journal"
	_scope = "turn-photo-v1:" + _owner + ":" + room_id + ":" + str(accepted.turn_id)
	var loaded: Variant = _load.call(_scope)
	if not loaded is Dictionary or not loaded.get("ok", false):
		read_only = true
		return _finish(ticket, _fail("storage_unavailable"))
	var value: Variant = loaded.get("value") if loaded.get("found", false) else {"schema_version": 1, "target": accepted, "selection": {}, "pending": {}, "cleanup": [], "last_receipt": {}}
	if not _valid_state(value, accepted):
		read_only = true
		return _finish(ticket, _fail("unsupported_save"))
	_state = value.duplicate(true)
	return _finish(ticket, true)

func choose_local(metadata: Dictionary, captured_context: Dictionary) -> bool:
	if not _can_mutate() or captured_context != selection_context() or not Capture._metadata_valid(metadata):
		return _fail("invalid_local_photo")
	var next := _state.duplicate(true)
	var prior: String = next.selection.get("photo_id", "")
	if prior != "" and prior != metadata.photo_id:
		_queue_cleanup(next, prior)
	# A reselected local image must not be removed by a previous cleanup entry.
	next.cleanup.erase(metadata.photo_id)
	next.selection = metadata.duplicate(true)
	return _persist(next)

func skip_local() -> bool:
	if not _can_mutate():
		return false
	var next := _state.duplicate(true)
	if not next.selection.is_empty():
		_queue_cleanup(next, next.selection.photo_id)
	next.selection = {}
	return _persist(next)

func refresh_photo() -> bool:
	var ticket := _begin()
	if ticket < 0:
		return false
	return _finish(ticket, await _refresh(ticket))

func upload_selected() -> bool:
	if not _can_mutate() or _state.selection.is_empty():
		return _fail("select_photo_first")
	var ticket := _begin()
	if ticket < 0:
		return false
	# Read latest revision immediately before forming the proposal. Server CAS
	# still decides any race after this observation.
	if not await _refresh(ticket):
		return _finish(ticket, false)
	var selected: Dictionary = _state.selection.duplicate(true)
	var local: Variant = await _local.call("read", selected.photo_id)
	if not _same(ticket):
		return false
	if not local is Dictionary or not local.get("ok", false) or not Canonical.same(local.get("metadata"), selected) or not local.get("bytes") is PackedByteArray:
		return _finish(ticket, _fail("local_photo_unavailable"))
	var bytes: PackedByteArray = local.bytes
	if bytes.size() != selected.byte_count or bytes.size() > MAX_BYTES or _digest(bytes) != selected.sha256:
		return _finish(ticket, _fail("invalid_local_photo"))
	if not keep_selected_bytes(selected, bytes):
		return _finish(ticket, _fail("storage_unavailable"))
	var body := _mutation_body()
	body.jpeg_base64 = Marshalls.raw_to_base64(bytes)
	body.sha256 = selected.sha256
	if not _stage("photo_upload", body, selected.photo_id):
		return _finish(ticket, false)
	return _finish(ticket, await _send_pending(ticket))

func delete_photo() -> bool:
	if not _can_mutate():
		return false
	var ticket := _begin()
	if ticket < 0:
		return false
	if not await _refresh(ticket):
		return _finish(ticket, false)
	if not _photo is Dictionary or _photo.sha256 == null:
		return _finish(ticket, _fail("photo_not_found"))
	if not _stage("photo_delete", _mutation_body(), ""):
		return _finish(ticket, false)
	return _finish(ticket, await _send_pending(ticket))

func reconcile() -> bool:
	if not _guard() or read_only or _state.pending.is_empty():
		return _fail("no_pending_photo")
	var ticket := _begin()
	if ticket < 0:
		return false
	var response := await _net(HTTPClient.METHOD_GET, _room_path() + "/photo-operations/" + str(_state.pending.body.idempotency_key), {}, ticket)
	if not _same(ticket):
		return false
	if response.get("ok", false):
		return _finish(ticket, _accept(response.get("data")))
	if response.get("status") == 404 and response.get("code") == "photo_operation_not_found":
		# No new key, bytes, expected revision or recording after an uncertain ack.
		return _finish(ticket, await _send_pending(ticket))
	return _finish(ticket, _response_error(response))

func abandon_rejected_request() -> bool:
	if not _guard() or _busy or read_only or _state.pending.is_empty() or not _state.pending.held:
		return _fail("pending_photo_unresolved")
	var next := _state.duplicate(true)
	next.pending = {}
	return _persist(next)

func cleanup_local() -> bool:
	var ticket := _begin()
	if ticket < 0:
		return false
	for photo_id: String in _state.cleanup.duplicate():
		var result: Variant = await _local.call("discard", photo_id)
		if not _same(ticket):
			return false
		if not result is Dictionary or not result.get("ok", false) or not result.get("discarded", false):
			return _finish(ticket, _fail("local_cleanup_pending"))
		var next := _state.duplicate(true)
		next.cleanup.erase(photo_id)
		if not _persist(next):
			return _finish(ticket, false)
	return _finish(ticket, true)

func read_shared(room_id: String, turn_id: String, recording_hash: String) -> Dictionary:
	# Call with the exact turn/hash from a replay-verified room/pair, not inferred
	# from the currently visible role. GET independently enforces membership.
	if not _id(room_id) or not _turn(turn_id) or not _hash(recording_hash):
		_fail("invalid_target")
		return {}
	var ticket := _begin(true)
	if ticket < 0:
		return {}
	var result := await _read_photo(room_id, {"turn_id": turn_id, "recording_hash": recording_hash}, ticket)
	_finish(ticket, not result.is_empty())
	return result

func _refresh(ticket: int) -> bool:
	var result := await _read_photo(str(_state.target.room_id), _state.target, ticket, true)
	if result.is_empty():
		_image = PackedByteArray()
		_observed = false
		return false
	_photo = result.photo
	_image = result.bytes
	_observed = true
	return true

func _read_photo(room_id: String, expected: Dictionary, ticket: int, require_current: bool = false) -> Dictionary:
	var path := "/v2/rooms/" + room_id + "/photos/" + str(expected.turn_id)
	var cached: Dictionary = {}
	if _library != null:
		# Revalidate small metadata to notice replacement/removal. JPEG bytes are
		# requested only for a missing version, never for an ordinary cached replay.
		var delivery := await _net(HTTPClient.METHOD_GET, path + "/delivery", {}, ticket)
		if not _same(ticket): return {}
		if delivery.get("ok", false):
			var info: Variant = delivery.get("data")
			if not _valid_delivery(info, expected):
				_fail("invalid_photo_response")
				return {}
			if info.photo == null or info.photo.sha256 == null:
				if info.photo is Dictionary:
					var removed: Dictionary = _library.mark_deleted(_owner, room_id, info.photo)
					if not removed.get("ok", false): _fail("storage_unavailable")
				return {"photo": info.photo, "bytes": PackedByteArray()}
			cached = _library.read_cache(_owner, room_id, info.photo)
			if cached.get("ok", false) and cached.get("found", false):
				await _ack_cached(room_id, cached, ticket)
				return {"photo": cached.photo, "bytes": cached.bytes} if _same(ticket) else {}
			if not info.available:
				_fail("photo_payload_delivered")
				return {}
		elif not (delivery.get("status") == 404 and delivery.get("code") == "not_found"):
			# Offline display may use verified local bytes. Editing always requires
			# a fresh revision so a connection failure cannot form a stale mutation.
			if not require_current and int(delivery.get("status", 0)) in [0, 429, 500, 502, 503, 504]:
				cached = _library.read_cache(_owner, room_id, expected)
				if cached.get("ok", false) and cached.get("found", false):
					return {"photo": cached.photo, "bytes": cached.bytes}
			_response_error(delivery)
			return {}
	var response := await _net(HTTPClient.METHOD_GET, path, {}, ticket)
	if not _same(ticket): return {}
	if not response.get("ok", false):
		_response_error(response)
		return {}
	var result := _read_payload(response.get("data"), expected)
	if result.is_empty():
		_fail("invalid_photo_response")
		return {}
	if _library != null and result.photo is Dictionary and result.photo.sha256 == null:
		var removed: Dictionary = _library.mark_deleted(_owner, room_id, result.photo)
		if not removed.get("ok", false): _fail("storage_unavailable")
	if _library != null and not result.bytes.is_empty():
		var saved: Dictionary = _library.store_cache(_owner, room_id, result.photo, result.bytes)
		if not saved.get("ok", false) or not saved.get("durable", false):
			_fail("storage_unavailable")
			return result # View once, but never ACK a non-durable download.
		cached = _library.read_cache(_owner, room_id, result.photo)
		await _ack_cached(room_id, cached, ticket)
	return result if _same(ticket) else {}

func _valid_delivery(value: Variant, expected: Dictionary, acknowledgement: bool = false) -> bool:
	var keys := ["schema_version", "photo", "available", "removed_reason", "intended_player_ids", "acked_player_ids"]
	if acknowledgement: keys.append("acked")
	if not value is Dictionary or not _exact(value, keys) or value.schema_version != 1 or not _metadata(value.photo, expected) or not value.available is bool or value.removed_reason not in [null, "delivered", "owner_deleted"] or not value.intended_player_ids is Array or not value.acked_player_ids is Array:
		return false
	if value.intended_player_ids.is_empty() or value.intended_player_ids.size() > 2 or value.acked_player_ids.size() > 2 or _owner not in value.intended_player_ids: return false
	var seen: Array = []
	for player: Variant in value.intended_player_ids:
		if not _id(player) or player in seen: return false
		seen.append(player)
	seen.clear()
	for player: Variant in value.acked_player_ids:
		if player not in value.intended_player_ids or player in seen: return false
		seen.append(player)
	return not acknowledgement or value.acked == true

func _ack_cached(room_id: String, cached: Dictionary, ticket: int) -> void:
	if not _same(ticket) or _library == null or not cached.get("ok", false) or not cached.get("found", false) or cached.get("delivery_ack", false): return
	var photo: Dictionary = cached.get("photo", {})
	if not _metadata(photo, photo) or photo.get("sha256") == null or not cached.get("entry_id") is String: return
	# read_cache rechecks file bytes and durable provenance, including after a
	# restart or a previously lost ACK response.
	var body := {"recording_hash": photo.recording_hash, "photo_revision": photo.photo_revision, "sha256": photo.sha256}
	var response := await _net(HTTPClient.METHOD_POST, "/v2/rooms/" + room_id + "/photos/" + str(photo.turn_id) + "/ack", body, ticket)
	if not _same(ticket) or not response.get("ok", false): return
	var info: Variant = response.get("data")
	if _valid_delivery(info, photo, true) and info.photo != null and info.photo.photo_revision == photo.photo_revision and info.photo.sha256 == photo.sha256 and _owner in info.acked_player_ids:
		_library.mark_ack(_owner, cached.entry_id)

func _mutation_body() -> Dictionary:
	return {"idempotency_key": str(_keys.call()) if _keys.is_valid() else Crypto.new().generate_random_bytes(18).hex_encode(), "recording_hash": _state.target.recording_hash,
		"expected_photo_revision": int(_photo.photo_revision) if _photo is Dictionary else 0, "expected_photo_hash": _photo.sha256 if _photo is Dictionary else null}

func _stage(operation: String, body: Dictionary, photo_id: String) -> bool:
	if not _observed or not _key(body.idempotency_key):
		return _fail("invalid_photo_request")
	var next := _state.duplicate(true)
	var material := body.duplicate(true)
	material.merge({"operation": operation, "turn_id": _state.target.turn_id})
	next.pending = {"operation": operation, "body": body, "request_hash": Canonical.digest(material), "local_photo_id": photo_id, "held": false}
	return _persist(next) # Complete immutable bytes durable before first POST.

func _send_pending(ticket: int) -> bool:
	var request: Dictionary = _state.pending.duplicate(true)
	var response := await _net(HTTPClient.METHOD_POST if request.operation == "photo_upload" else HTTPClient.METHOD_DELETE, _photo_path(), request.body, ticket)
	if not _same(ticket):
		return false
	if response.get("ok", false):
		var accepted := _accept(response.get("data"))
		if accepted and _library != null and request.operation == "photo_upload":
			var cached: Dictionary = _library.read_cache(_owner, str(_state.target.room_id), {"turn_id": _state.target.turn_id, "recording_hash": _state.target.recording_hash, "sha256": request.body.sha256, "photo_revision": int(request.body.expected_photo_revision) + 1})
			await _ack_cached(str(_state.target.room_id), cached, ticket)
		return accepted and _same(ticket)
	if int(response.get("status", 0)) in [400, 409, 404] and response.get("code") in ["stale_photo_revision", "photo_recording_mismatch", "photo_not_found", "turn_not_found", "photo_room_full", "photo_history_full", "invalid_photo_encoding", "invalid_photo_checksum", "photo_checksum_mismatch", "invalid_photo_jpeg", "photo_size_limit", "photo_dimensions_limit", "photo_metadata_not_allowed", "unsupported_photo_format"]:
		var next := _state.duplicate(true)
		next.pending.held = true
		if not _persist(next):
			return false
	return _response_error(response)

func _accept(value: Variant) -> bool:
	if not value is Dictionary or not _exact(value, ["receipt", "photo"]) or not _valid_receipt(value.get("receipt")) or not _metadata(value.get("photo"), _state.target):
		return _fail("photo_receipt_mismatch")
	var request: Dictionary = _state.pending
	var receipt: Dictionary = value.receipt
	var expected_hash: Variant = request.body.get("sha256") if request.operation == "photo_upload" else null
	if receipt.operation != request.operation or receipt.idempotency_key != request.body.idempotency_key or receipt.request_hash != request.request_hash or receipt.photo_revision != int(request.body.expected_photo_revision) + 1 or receipt.photo_hash != expected_hash:
		return _fail("photo_receipt_mismatch")
	# Receipt describes the immutable operation; current photo may be newer.
	if value.photo == null or value.photo.photo_revision < receipt.photo_revision or (value.photo.photo_revision == receipt.photo_revision and value.photo.sha256 != receipt.photo_hash):
		return _fail("photo_receipt_mismatch")
	if _library != null:
		if request.operation == "photo_upload" and value.photo.photo_revision == receipt.photo_revision:
			var saved: Dictionary = _library.store_cache(_owner, str(_state.target.room_id), value.photo, _decode(request.body.jpeg_base64, request.body.sha256))
			if not saved.get("ok", false) or not saved.get("durable", false): return _fail("storage_unavailable")
		elif value.photo.sha256 == null:
			var removed: Dictionary = _library.mark_deleted(_owner, str(_state.target.room_id), value.photo)
			if not removed.get("ok", false): return _fail("storage_unavailable")
	var next := _state.duplicate(true)
	if request.local_photo_id != "":
		_queue_cleanup(next, request.local_photo_id)
		if next.selection.get("photo_id") == request.local_photo_id:
			next.selection = {}
	next.pending = {}
	next.last_receipt = receipt.duplicate(true)
	if not _persist(next):
		return false # Accepted but local ack failed: retain exact retryable request.
	_photo = value.photo.duplicate(true)
	_image = PackedByteArray() # Never show old pixels with newer metadata.
	_observed = false
	return true

func _accepted_target(value: Variant, room: String, key: String) -> Dictionary:
	if not value is Dictionary or not _exact(value, ["receipt", "room"]) or not value.receipt is Dictionary or not value.room is Dictionary:
		return {}
	var r: Dictionary = value.receipt
	var s: Dictionary = value.room
	var keys := ["schema_version", "room_id", "idempotency_key", "request_hash", "operation", "accepted_revision", "branch", "stage_index", "stage_id", "turn_id", "recording_hash", "pair_id", "checkpoint_hash"]
	if not _exact(r, keys) or r.schema_version != 2 or r.operation != "turns" or r.room_id != room or r.idempotency_key != key or not _hash(r.request_hash) or not _hash(r.recording_hash) or not _hash(r.checkpoint_hash) or not _range(r.branch, 0, 31) or not _range(r.stage_index, 0, 1) or not _range(r.accepted_revision, 1, 256) or not _turn(r.turn_id):
		return {}
	var chapter := Registry.resolve(s)
	if chapter.is_empty(): return {}
	var level := Registry.definition(chapter)
	var role: String = str(r.turn_id).right(1)
	var index := int(r.stage_index)
	if r.turn_id != "t%d-%d-%s" % [int(r.branch), index, role] or r.stage_id != level.stages[index].id or r.pair_id != ("p%d-%d" % [int(r.branch), index] if role == "b" else null):
		return {}
	if s.get("api_version") != 2 or s.get("schema_version") != 2 or s.get("room_id") != room or not _range(s.get("revision"), int(r.accepted_revision), 256) or _owner not in [s.get("host_id"), s.get("guest_id")]:
		return {}
	var first: Variant = s.get("host_id") if level.stages[index].first_player_slot == "p0" else s.get("guest_id")
	var second: Variant = s.get("guest_id") if level.stages[index].first_player_slot == "p0" else s.get("host_id")
	if _owner != (first if role == "a" else second):
		return {}
	return {"room_id": room, "turn_id": r.turn_id, "recording_hash": r.recording_hash, "owner_player_id": _owner, "branch": r.branch, "stage_index": index, "stage_id": r.stage_id, "role": role, "gameplay_key": key}

func _read_payload(value: Variant, expected: Dictionary) -> Dictionary:
	if not value is Dictionary or not _exact(value, ["photo", "jpeg_base64"]) or not _metadata(value.photo, expected):
		return {}
	if value.photo == null or value.photo.sha256 == null:
		return {"photo": value.photo, "bytes": PackedByteArray()} if value.jpeg_base64 == null else {}
	var bytes := _decode(value.jpeg_base64, value.photo.sha256)
	if bytes.is_empty() or bytes.size() != value.photo.byte_length:
		return {}
	return {"photo": value.photo.duplicate(true), "bytes": bytes}

func _metadata(value: Variant, expected: Dictionary) -> bool:
	if value == null:
		return true
	if not value is Dictionary or not _exact(value, META_KEYS) or value.schema_version != 1 or value.turn_id != expected.turn_id or value.recording_hash != expected.recording_hash or not _id(value.owner_player_id) or (expected.has("owner_player_id") and value.owner_player_id != expected.owner_player_id) or not _range(value.photo_revision, 1, 256) or not value.updated_at is String or value.updated_at.length() > 32:
		return false
	if value.sha256 == null:
		return value.width == null and value.height == null and value.byte_length == 0
	return _hash(value.sha256) and _range(value.width, 1, 960) and _range(value.height, 1, 960) and _range(value.byte_length, 1, MAX_BYTES)

func _valid_receipt(value: Variant) -> bool:
	return value is Dictionary and _exact(value, RECEIPT_KEYS) and value.schema_version == 1 and value.room_id == _state.target.room_id and value.turn_id == _state.target.turn_id and value.recording_hash == _state.target.recording_hash and _key(value.idempotency_key) and _hash(value.request_hash) and value.operation in ["photo_upload", "photo_delete"] and _range(value.photo_revision, 1, 256) and (value.photo_hash == null if value.operation == "photo_delete" else _hash(value.photo_hash))

func _valid_state(value: Variant, expected: Dictionary) -> bool:
	if not value is Dictionary or JSON.stringify(value).to_utf8_buffer().size() > MAX_STATE or not _exact(value, STATE_KEYS) or value.schema_version != 1 or not Canonical.same(value.target, expected) or not value.selection is Dictionary or (not value.selection.is_empty() and not Capture._metadata_valid(value.selection)) or not value.cleanup is Array or value.cleanup.size() > 16 or not value.last_receipt is Dictionary or not value.pending is Dictionary:
		return false
	var seen: Array = []
	for id: Variant in value.cleanup:
		if not Capture._matches(id, "^[a-f0-9]{32}$") or id in seen or id == value.selection.get("photo_id"):
			return false
		seen.append(id)
	if not value.last_receipt.is_empty():
		var saved_state: Dictionary = _state
		_state = value
		var valid := _valid_receipt(value.last_receipt)
		_state = saved_state
		if not valid:
			return false
	if value.pending.is_empty():
		return true
	var p: Dictionary = value.pending
	if not _exact(p, ["operation", "body", "request_hash", "local_photo_id", "held"]) or p.operation not in ["photo_upload", "photo_delete"] or not p.body is Dictionary or not p.held is bool:
		return false
	var body: Dictionary = p.body
	var required := ["idempotency_key", "recording_hash", "expected_photo_revision", "expected_photo_hash"]
	if p.operation == "photo_upload":
		required.append_array(["jpeg_base64", "sha256"])
	if not _exact(body, required) or not _key(body.idempotency_key) or body.recording_hash != expected.recording_hash or not _range(body.expected_photo_revision, 0, 255) or (body.expected_photo_hash != null and not _hash(body.expected_photo_hash)):
		return false
	if p.operation == "photo_upload":
		if not Capture._matches(p.local_photo_id, "^[a-f0-9]{32}$") or p.local_photo_id != value.selection.get("photo_id") or body.sha256 != value.selection.get("sha256") or _decode(body.jpeg_base64, body.sha256).size() != value.selection.get("byte_count"):
			return false
	elif p.local_photo_id != "":
		return false
	var material := body.duplicate(true)
	material.merge({"operation": p.operation, "turn_id": expected.turn_id})
	return p.request_hash == Canonical.digest(material)

func _persist(next: Dictionary) -> bool:
	if not _guard() or read_only or not _valid_state(next, _state.target):
		return _fail("unsupported_save")
	var saved: Variant = _save.call(_scope, next.duplicate(true))
	if not saved is Dictionary or not saved.get("ok", false):
		return _fail("storage_unavailable")
	_state = next.duplicate(true)
	return true

func _queue_cleanup(next: Dictionary, id: String) -> void:
	if id not in next.cleanup:
		next.cleanup.append(id) # Full queue fails validation; never silently drops IDs.

func _begin(unbound: bool = false) -> int:
	var identity: Variant = _identity.call()
	if not identity is Dictionary or not identity.get("ready", false) or not _id(identity.get("player_id")) or not _range(identity.get("epoch"), 0, 2147483647):
		invalidate_identity()
		return -1
	if _owner != identity.player_id or _epoch != int(identity.epoch):
		invalidate_identity()
		_owner = identity.player_id
		_epoch = int(identity.epoch)
	if _busy or (not unbound and (_state.is_empty() or read_only)):
		_fail("photo_busy" if _busy else "photo_unavailable")
		return -1
	_busy = true
	return _generation

func _guard() -> bool:
	if _state.is_empty():
		return false
	return _same(_generation)

func _same(ticket: int) -> bool:
	var identity: Variant = _identity.call()
	if ticket != _generation:
		return false
	if not identity is Dictionary or not identity.get("ready", false) or identity.get("player_id") != _owner or identity.get("epoch") != _epoch:
		invalidate_identity()
		return false
	return true

func _can_mutate() -> bool:
	return _guard() and not _busy and not read_only and _state.pending.is_empty()

func _finish(ticket: int, result: bool) -> bool:
	if not _same(ticket):
		return false
	_busy = false
	if result:
		last_error = ""
		last_code = ""
	return result

func _net(method: int, path: String, body: Dictionary, ticket: int) -> Dictionary:
	if not _same(ticket):
		return {"ok": false, "code": "identity_changed"}
	var response: Variant = await _transport.call({"method": method, "path": path, "body": body.duplicate(true), "owner_player_id": _owner, "identity_epoch": _epoch})
	if not _same(ticket):
		return {"ok": false, "code": "identity_changed"}
	return response if response is Dictionary else {"ok": false, "code": "invalid_photo_response"}

func _response_error(response: Dictionary) -> bool:
	if response.get("status") == 401:
		invalidate_identity()
		return false
	return _fail(str(response.get("code", "photo_unavailable")))

func _fail(code: String) -> bool:
	var messages := {"identity_changed": "Reload or recover your identity before accessing photos.", "storage_unavailable": "The photo request could not be saved. Your game contribution is unaffected.", "unsupported_save": "This saved photo request needs a compatible app. It has been kept unchanged.", "unsupported_target": "This contribution needs a compatible app or an accepted turn receipt.", "photo_receipt_mismatch": "The photo reply did not match the saved request. Check it again before making a replacement.", "stale_photo_revision": "This photo changed elsewhere. Discard the rejected photo request, then review the current image.", "photo_room_full": "This room has reached its photo limit. Existing memories remain available.", "photo_history_full": "This room has reached its photo edit limit. Existing memories remain available.", "local_cleanup_pending": "The saved local copy could not be removed yet. Try local cleanup again.", "local_photo_unavailable": "The local photo expired or could not be read. Choose another photo.", "v2_mutations_disabled": "New photo uploads are paused. Your game contribution is already saved.", "not_found": "Photo sharing is not available from this service yet.", "photo_busy": "Wait for the current photo request.", "rate_limited": "Wait a little before checking this photo again.", "photo_not_found": "No photo is attached to this turn.", "pending_photo_unresolved": "Check the saved photo request before replacing it."}
	messages["request_busy"] = "Another room update is finishing. Try photo again in a moment. Your kept photo has not been changed."
	messages["operation_not_found"] = "The service could not find this contribution's saved receipt. Return to rooms and refresh before trying again. Your kept photo is unchanged."
	messages["connection_interrupted"] = "The photo service could not be reached. Try again when connected; your kept photo and game contribution are unchanged."
	messages["photo_payload_delivered"] = "This photo was delivered to the original phones. Receive its temporary photo transfer on this phone, if one was prepared."
	last_code = code if code in messages or code in ["select_photo_first", "invalid_target", "invalid_local_photo", "invalid_photo_request", "invalid_photo_response", "photo_unavailable", "connection_interrupted", "photo_operation_not_found", "room_not_found", "turn_not_found", "photo_recording_mismatch", "idempotency_key_reused", "request_busy", "no_pending_photo"] else "photo_unavailable"
	last_error = str(messages.get(last_code, "The photo is unavailable. Retry or skip it; your game contribution is unaffected."))
	return false

func _room_path() -> String:
	return "/v2/rooms/" + str(_state.target.room_id)

func _photo_path() -> String:
	return _room_path() + "/photos/" + str(_state.target.turn_id)

static func _decode(encoded: Variant, hash: Variant) -> PackedByteArray:
	if not encoded is String or encoded.length() > 218456 or not _hash(hash) or not Capture._matches(encoded, "^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$"):
		return PackedByteArray()
	var bytes := Marshalls.base64_to_raw(encoded)
	return bytes if bytes.size() >= 1 and bytes.size() <= MAX_BYTES and Marshalls.raw_to_base64(bytes) == encoded and _digest(bytes) == hash else PackedByteArray()

static func _digest(bytes: PackedByteArray) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	return hash.finish().hex_encode()

static func _exact(value: Dictionary, keys: Array) -> bool:
	return value.size() == keys.size() and keys.all(func(key: String) -> bool: return value.has(key))

static func _id(value: Variant) -> bool:
	return Capture._matches(value, "^[A-Za-z0-9_-]{22}$")

static func _key(value: Variant) -> bool:
	return Capture._matches(value, "^[A-Za-z0-9_-]{16,80}$")

static func _hash(value: Variant) -> bool:
	return Capture._matches(value, "^[a-f0-9]{64}$")

static func _turn(value: Variant) -> bool:
	return Capture._matches(value, "^t(?:[0-9]|[12][0-9]|3[01])-[01]-[ab]$")

static func _range(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= low and value <= high and value == int(value)
