class_name PhotoTransferClient
extends RefCounted
const PlayerCopy = preload("res://presentation/player_copy.gd")
## Explicit, resumable photo transfer. All durable state is account-scoped.
signal progress(message: String)
const Save = preload("res://services/local_save.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const BASE := "/v1/photo-transfer"
const BODY_LIMIT := 800 * 1024
const MAX_ENTRIES := 1000
const REQUEST_INTERVAL_MS := 1100 # Below the shared 60 requests/minute limit.
var busy := false
var message := PlayerCopy.PHOTO_TRANSFER_CLIENT_DF5BE7983DE5
var inventory: Dictionary = {}
var _transport: Callable
var _identity: Callable
var _library: RefCounted
var _directory: String
var _save: RefCounted
var _state: Dictionary = {}
var _owner := ""
var _epoch := -1
var _generation := 0
var _request_interval_ms: int
var _clock: Callable
var _sleep: Callable
var _next_request_ms := 0

func _init(transport: Callable, identity: Callable, library: RefCounted, directory: String = "user://photo-transfer", request_interval_ms: int = REQUEST_INTERVAL_MS, clock: Callable = Callable(), sleeper: Callable = Callable()) -> void:
	_transport = transport
	_identity = identity
	_library = library
	_directory = directory
	_request_interval_ms = maxi(0, request_interval_ms)
	_clock = clock
	_sleep = sleeper

func invalidate() -> void:
	_generation += 1
	busy = false
	_owner = ""
	_epoch = -1
	_save = null
	_state = {}
	inventory = {}

func _bound() -> bool:
	var value: Variant = _identity.call() if _identity.is_valid() else null
	if not value is Dictionary or not value.get("ready", false) or not _id(value.get("player_id")):
		return false
	if _owner != value.player_id or _epoch != int(value.get("epoch", -1)):
		invalidate()
		_owner = value.player_id
		_epoch = int(value.get("epoch", -1))
		if DirAccess.make_dir_recursive_absolute(_directory) != OK: return false
		var path := _directory.path_join(_owner.sha256_text() + ".json")
		var found := false
		for suffix: String in ["", ".tmp", ".backup"]:
			if FileAccess.file_exists(path + suffix):
				found = true
				var file := FileAccess.open(path + suffix, FileAccess.READ)
				if file == null or file.get_length() > 3 * 1024 * 1024: return false
				var parser := JSON.new()
				var parsed := parser.parse(file.get_as_text())
				file.close()
				# Do not recover over an understandable future/invalid transfer
				# generation, even when an older envelope is otherwise loadable.
				if parsed == OK and parser.data is Dictionary:
					if parser.data.get("version") != 1 or (parser.data.has("photo_transfer") and not _valid_state(parser.data.photo_transfer)): return false
		_save = Save.new(path)
		_save.load_data()
		if _save.read_only or (found and _save.loaded_from.is_empty()): return false
		var saved: Variant = _save.data.get("photo_transfer", {"schema_version": 1, "owner": _owner, "upload": {}, "pending": {}})
		if not _valid_state(saved): return false
		_state = saved.duplicate(true)
	return _save != null and not _state.is_empty()

func _persist(next: Dictionary) -> bool:
	if not _same(_generation) or _save == null or not _valid_state(next) or JSON.stringify(next).to_utf8_buffer().size() > 2800 * 1024:
		return false
	if not _save.update_values({"photo_transfer": next.duplicate(true)}): return false
	_state = next.duplicate(true)
	return true

func local_entries() -> Dictionary:
	if not _bound(): return {"ok": false, "entries": []}
	return _library.list_entries(_owner)

func has_pending_upload() -> bool:
	return _bound() and not _state.upload.is_empty()

func has_pending_work() -> bool:
	return _bound() and (not _state.upload.is_empty() or not _state.pending.is_empty())

func abandon_local_plan() -> bool:
	# Explicit user action only. Original local photos and any server copies are
	# left intact; abandoned server items still expire under the service policy.
	if busy or not _bound(): return false
	var next := _state.duplicate(true)
	next.upload = {}
	next.pending = {}
	if not _persist(next): return _storage_error()
	_say(PlayerCopy.PHOTO_TRANSFER_CLIENT_E6F94A342A5A)
	return true

func _begin() -> int:
	if busy: return -1
	if not _bound():
		_say(PlayerCopy.PHOTO_TRANSFER_CLIENT_02697535A42C)
		return -1
	busy = true
	return _generation

func _same(ticket: int) -> bool:
	var value: Dictionary = _identity.call() if _identity.is_valid() else {}
	return ticket == _generation and value.get("ready", false) and value.get("player_id") == _owner and int(value.get("epoch", -1)) == _epoch

func _finish(ticket: int, ok: bool) -> bool:
	if not _same(ticket): return false
	busy = false
	progress.emit(message)
	return ok

func _say(text: String) -> void:
	message = text
	progress.emit(text)

func _net(method: int, path: String, body: Dictionary, ticket: int) -> Dictionary:
	if not await _wait_for_slot(ticket): return {"ok": false, "code": "identity_changed"}
	_next_request_ms = _now_ms() + _request_interval_ms
	var response: Variant = await _transport.call(method, path, body.duplicate(true))
	if not _same(ticket): return {"ok": false, "code": "identity_changed"}
	if response is Dictionary and int(response.get("status", 0)) == 429 and response.get("code") not in ["transfer_cooldown", "transfer_session_cooldown"]:
		_next_request_ms = maxi(_next_request_ms, _now_ms() + clampi(int(response.get("retry_after_ms", 60000)), 1000, 86400000))
	return response if response is Dictionary else {"ok": false, "code": "invalid_response"}

func _now_ms() -> int:
	return int(_clock.call()) if _clock.is_valid() else Time.get_ticks_msec()

func _wait_for_slot(ticket: int) -> bool:
	while _same(ticket) and _now_ms() < _next_request_ms:
		var delay := mini(100, _next_request_ms - _now_ms())
		if _sleep.is_valid():
			await _sleep.call(delay)
		else:
			var tree := Engine.get_main_loop() as SceneTree
			if tree == null: return false
			# Small timer slices keep Back/account changes cancellable. There is
			# no automatic retry: every error returns to the player immediately.
			await tree.create_timer(delay / 1000.0, true, false, true).timeout
	return _same(ticket)

func _error(response: Dictionary) -> bool:
	var code := str(response.get("code", "connection_interrupted"))
	if code in ["transfer_cooldown", "transfer_session_cooldown"]:
		_say(PlayerCopy.PHOTO_TRANSFER_CLIENT_B1FA7A4A3DFA)
	elif code == "rate_limited" or int(response.get("status", 0)) == 429:
		var seconds := maxi(1, ceili(int(response.get("retry_after_ms", 60000)) / 1000.0))
		_say(PlayerCopy.PHOTO_TRANSFER_CLIENT_AD42010C79B5 % seconds)
	elif code.contains("capacity") or code.contains("full"):
		_say(PlayerCopy.PHOTO_TRANSFER_CLIENT_BB4817187B13)
	elif code.contains("expired") or code == "transfer_session_not_found":
		_say(PlayerCopy.PHOTO_TRANSFER_CLIENT_F9A4A829D88A)
	elif code in ["invalid_auth", "identity_changed"]:
		_say(PlayerCopy.PHOTO_TRANSFER_CLIENT_2BF67E9A3F2E)
	else:
		_say(PlayerCopy.PHOTO_TRANSFER_CLIENT_852AB0CE2F74)
	return false

func refresh() -> bool:
	var ticket := _begin()
	if ticket < 0: return false
	_say(PlayerCopy.PHOTO_TRANSFER_CLIENT_4DEDA82BAEA1)
	var response := await _net(HTTPClient.METHOD_GET, BASE, {}, ticket)
	if not response.get("ok", false): return _finish(ticket, _error(response))
	if not _valid_inventory(response.get("data")):
		_say(PlayerCopy.PHOTO_TRANSFER_CLIENT_4CC75B629CEB)
		return _finish(ticket, false)
	inventory = response.data.duplicate(true)
	_say(PlayerCopy.PHOTO_TRANSFER_CLIENT_CE374AA315A9 % int(inventory.entry_count) if inventory.entry_count > 0 else PlayerCopy.PHOTO_TRANSFER_CLIENT_318D68E3863C)
	return _finish(ticket, true)

func prepare() -> bool:
	var ticket := _begin()
	if ticket < 0: return false
	if not _state.upload.is_empty() or not _state.pending.is_empty():
		_say(PlayerCopy.PHOTO_TRANSFER_CLIENT_15570FF9F693)
		return _finish(ticket, false)
	var local: Dictionary = _library.list_entries(_owner)
	if not local.get("ok", false) or local.get("entries", []).is_empty():
		_say(PlayerCopy.PHOTO_TRANSFER_CLIENT_73B2C3320E73)
		return _finish(ticket, false)
	var ids: Array = []
	for entry: Dictionary in local.entries.slice(0, MAX_ENTRIES): ids.append(entry.entry_id)
	var next := _state.duplicate(true)
	next.upload = {"start_key": _key(), "session_id": "", "entry_ids": ids, "cursor": 0}
	if not _persist(next): return _finish(ticket, _storage_error())
	return _finish(ticket, await _upload(ticket))

func resume_upload() -> bool:
	var ticket := _begin()
	if ticket < 0: return false
	if _state.upload.is_empty():
		_say(PlayerCopy.PHOTO_TRANSFER_CLIENT_78AD3668830A)
		return _finish(ticket, false)
	return _finish(ticket, await _upload(ticket))

func _upload(ticket: int) -> bool:
	if _state.upload.session_id == "":
		_say(PlayerCopy.PHOTO_TRANSFER_CLIENT_B2AB55C00617)
		var response := await _net(HTTPClient.METHOD_POST, BASE + "/sessions", {"schema_version": 1, "idempotency_key": _state.upload.start_key}, ticket)
		if not response.get("ok", false): return _error(response)
		var session: Variant = response.get("data", {}).get("session")
		if not session is Dictionary or session.get("session_id") != _state.upload.start_key:
			_say(PlayerCopy.PHOTO_TRANSFER_CLIENT_6BF6BB0AE3B6)
			return false
		var next := _state.duplicate(true)
		next.upload.session_id = session.session_id
		if not _persist(next): return _storage_error()
	if not _state.pending.is_empty():
		if _state.pending.get("operation") != "upload":
			_say(PlayerCopy.PHOTO_TRANSFER_CLIENT_D2712625E9C0)
			return false
		if not await _send_pending(ticket): return false
	while _same(ticket) and int(_state.upload.cursor) < _state.upload.entry_ids.size():
		var body := {"schema_version": 1, "idempotency_key": _key(), "entries": []}
		var cursor := int(_state.upload.cursor)
		for index in range(cursor, mini(cursor + 16, _state.upload.entry_ids.size())):
			var exported: Dictionary = _library.export_entry(_owner, _state.upload.entry_ids[index])
			if not exported.get("ok", false):
				_say(PlayerCopy.PHOTO_TRANSFER_CLIENT_A2F984735D44)
				return false
			body.entries.append(exported.entry)
			if JSON.stringify(body).to_utf8_buffer().size() > BODY_LIMIT:
				body.entries.pop_back()
				break
		if body.entries.is_empty(): return _storage_error()
		var next := _state.duplicate(true)
		next.pending = {"operation": "upload", "path": BASE + "/" + str(next.upload.session_id) + "/entries", "body": body, "count": body.entries.size(), "session_id": next.upload.session_id}
		if not _persist(next): return _storage_error()
		_say("Preparing photo %d of %d…" % [cursor + 1, next.upload.entry_ids.size()])
		if not await _send_pending(ticket): return false
	if not _same(ticket): return false
	var count: int = _state.upload.entry_ids.size()
	var done := _state.duplicate(true)
	done.upload = {}
	if not _persist(done): return _storage_error()
	_say(PlayerCopy.PHOTO_TRANSFER_CLIENT_C62607E0EC74 % count)
	return true

func receive() -> bool:
	var ticket := _begin()
	if ticket < 0: return false
	if not _state.pending.is_empty():
		if _state.pending.get("operation") != "restore_ack":
			_say(PlayerCopy.PHOTO_TRANSFER_CLIENT_226CE43B8321)
			return _finish(ticket, false)
		if not await _send_pending(ticket): return _finish(ticket, false)
	_say(PlayerCopy.PHOTO_TRANSFER_CLIENT_21E01817A543)
	var response := await _net(HTTPClient.METHOD_GET, BASE, {}, ticket)
	if not response.get("ok", false): return _finish(ticket, _error(response))
	if not _valid_inventory(response.get("data")):
		_say(PlayerCopy.PHOTO_TRANSFER_CLIENT_EC826B26AF45)
		return _finish(ticket, false)
	var entries: Array = response.data.entries.duplicate(true)
	var cursor := 0
	while _same(ticket) and cursor < entries.size():
		var batch: Array = []
		var estimate := 0
		for index in range(cursor, mini(cursor + 16, entries.size())):
			var cost: int = ceili(float(entries[index].byte_length) / 3.0) * 4 + 2048
			if estimate + cost > BODY_LIMIT: break
			estimate += cost
			batch.append(entries[index])
		if batch.is_empty(): return _finish(ticket, _storage_error())
		_say("Receiving photo %d of %d…" % [cursor + 1, entries.size()])
		var ids: Array = batch.map(func(entry: Dictionary) -> String: return entry.entry_id)
		response = await _net(HTTPClient.METHOD_POST, BASE + "/read", {"schema_version": 1, "entry_ids": ids}, ticket)
		if not response.get("ok", false): return _finish(ticket, _error(response))
		var received: Variant = response.get("data", {}).get("entries")
		if not received is Array or received.size() != batch.size(): return _finish(ticket, _invalid_receive())
		var ack: Array = []
		var seen: Array = []
		for entry: Variant in received:
			if not entry is Dictionary or entry.get("entry_id") not in ids or entry.get("entry_id") in seen: return _finish(ticket, _invalid_receive())
			var expected: Dictionary = batch[ids.find(entry.entry_id)]
			var metadata: Dictionary = entry.duplicate(true)
			metadata.erase("jpeg_base64")
			if not Canonical.same(metadata, expected): return _finish(ticket, _invalid_receive())
			var portable: Dictionary = entry.duplicate(true)
			portable.erase("entry_revision")
			portable.erase("expires_at")
			var imported: Dictionary = _library.import_entry(_owner, portable)
			if not imported.get("ok", false) or not imported.get("durable", false): return _finish(ticket, _storage_error())
			seen.append(entry.entry_id)
			ack.append({"entry_id": entry.entry_id, "sha256": entry.sha256, "entry_revision": entry.entry_revision})
		var next := _state.duplicate(true)
		next.pending = {"operation": "restore_ack", "path": BASE + "/restore-ack", "session_id": null, "count": ack.size(), "body": {"schema_version": 1, "idempotency_key": _key(), "entries": ack}}
		if not _persist(next): return _finish(ticket, _storage_error())
		if not await _send_pending(ticket): return _finish(ticket, false)
		cursor += batch.size()
	_say(PlayerCopy.PHOTO_TRANSFER_CLIENT_40A26CED3E51 % cursor if cursor > 0 else PlayerCopy.PHOTO_TRANSFER_CLIENT_3F06A8AD2ED4)
	return _finish(ticket, true)

func _send_pending(ticket: int) -> bool:
	var pending: Dictionary = _state.pending.duplicate(true)
	if pending.operation == "restore_ack":
		# A process restart, disk cleanup or corruption can happen between the
		# durable import and a retried acknowledgement. Recheck every local file.
		for entry: Dictionary in pending.body.entries:
			var exported: Dictionary = _library.export_entry(_owner, entry.entry_id)
			if not exported.get("ok", false) or exported.get("entry", {}).get("sha256") != entry.sha256: return _storage_error()
	var response := await _net(HTTPClient.METHOD_POST, pending.path, pending.body, ticket)
	if not response.get("ok", false): return _error(response)
	var receipt: Variant = response.get("data", {}).get("receipt")
	if not receipt is Dictionary or receipt.get("idempotency_key") != pending.body.idempotency_key or receipt.get("operation") != pending.operation or receipt.get("session_id") != pending.session_id or not receipt.get("entries") is Array or receipt.entries.size() != pending.body.entries.size():
		_say(PlayerCopy.PHOTO_TRANSFER_CLIENT_EB45998E4C92)
		return false
	var material: Dictionary = pending.body.duplicate(true)
	material.merge({"operation": pending.operation, "session_id": pending.session_id})
	if receipt.get("request_hash") != Canonical.digest(material): return _invalid_receive()
	var by_id: Dictionary = {}
	for sent: Dictionary in pending.body.entries: by_id[sent.entry_id] = sent
	for accepted: Variant in receipt.entries:
		if not accepted is Dictionary or not by_id.has(accepted.get("entry_id")) or accepted.get("sha256") != by_id[accepted.entry_id].sha256 or not _positive_integer(accepted.get("entry_revision")): return _invalid_receive()
		if pending.operation == "restore_ack" and accepted.entry_revision != by_id[accepted.entry_id].entry_revision: return _invalid_receive()
		by_id.erase(accepted.entry_id)
	if not by_id.is_empty(): return _invalid_receive()
	var next := _state.duplicate(true)
	next.pending = {}
	if pending.operation == "upload": next.upload.cursor = int(next.upload.cursor) + int(pending.count)
	return _persist(next) or _storage_error()

func _valid_inventory(value: Variant) -> bool:
	if not value is Dictionary or value.get("schema_version") != 1 or not value.get("entries") is Array or value.entries.size() > MAX_ENTRIES or value.get("entry_count") != value.entries.size(): return false
	var seen: Array = []
	for entry: Variant in value.entries:
		if not entry is Dictionary or not _hash(entry.get("entry_id")) or not _hash(entry.get("sha256")) or entry.entry_id in seen or not _positive_integer(entry.get("entry_revision")) or not _positive_integer(entry.get("byte_length")) or entry.byte_length > 160 * 1024 or not entry.get("expires_at") is String: return false
		seen.append(entry.entry_id)
	return true

func _storage_error() -> bool:
	_say(PlayerCopy.PHOTO_TRANSFER_CLIENT_A2C045C29B14)
	return false

func _invalid_receive() -> bool:
	_say(PlayerCopy.PHOTO_TRANSFER_CLIENT_FFDC2731C383)
	return false

static func _key() -> String:
	return Crypto.new().generate_random_bytes(18).hex_encode()

static func _id(value: Variant) -> bool:
	return _matches(value, "^[A-Za-z0-9_-]{22}$")

static func _hash(value: Variant) -> bool:
	return _matches(value, "^[a-f0-9]{64}$")

static func _matches(value: Variant, pattern: String) -> bool:
	if not value is String: return false
	var expression := RegEx.new()
	expression.compile(pattern)
	var found := expression.search(value)
	return found != null and found.get_string() == value

static func _positive_integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value > 0 and value <= 2147483647 and value == int(value)

func _valid_state(value: Variant) -> bool:
	if not value is Dictionary or not _exact(value, ["schema_version", "owner", "upload", "pending"]) or value.schema_version != 1 or value.owner != _owner or not value.upload is Dictionary or not value.pending is Dictionary: return false
	var upload: Dictionary = value.upload
	if not upload.is_empty():
		if not _exact(upload, ["start_key", "session_id", "entry_ids", "cursor"]) or not _matches(upload.start_key, "^[A-Za-z0-9_-]{16,80}$") or upload.session_id not in ["", upload.start_key] or not upload.entry_ids is Array or upload.entry_ids.is_empty() or upload.entry_ids.size() > MAX_ENTRIES or not _integer(upload.cursor, 0, upload.entry_ids.size()): return false
		var seen: Array = []
		for id: Variant in upload.entry_ids:
			if not _hash(id) or id in seen: return false
			seen.append(id)
	var pending: Dictionary = value.pending
	if pending.is_empty(): return true
	if not _exact(pending, ["operation", "path", "session_id", "count", "body"]) or pending.operation not in ["upload", "restore_ack"] or not _integer(pending.count, 1, 16) or not pending.body is Dictionary or not _exact(pending.body, ["schema_version", "idempotency_key", "entries"]): return false
	var body: Dictionary = pending.body
	if body.schema_version != 1 or not _matches(body.idempotency_key, "^[A-Za-z0-9_-]{16,80}$") or not body.entries is Array or body.entries.size() != pending.count or JSON.stringify(body).to_utf8_buffer().size() > BODY_LIMIT: return false
	if pending.operation == "upload":
		if upload.is_empty() or upload.session_id == "" or pending.session_id != upload.session_id or pending.path != BASE + "/" + str(upload.session_id) + "/entries" or int(upload.cursor) + body.entries.size() > upload.entry_ids.size(): return false
	elif pending.session_id != null or pending.path != BASE + "/restore-ack": return false
	var seen: Array = []
	for index in range(body.entries.size()):
		var entry: Variant = body.entries[index]
		if not entry is Dictionary or not _hash(entry.get("entry_id")) or not _hash(entry.get("sha256")) or entry.entry_id in seen: return false
		seen.append(entry.entry_id)
		if pending.operation == "upload":
			if entry.entry_id != upload.entry_ids[int(upload.cursor) + index] or not _exact(entry, ["entry_id", "room_id", "turn_id", "recording_hash", "photo_revision", "photo_owner", "local_only", "sha256", "width", "height", "byte_length", "created_at", "jpeg_base64", "deleted"]) or not entry.jpeg_base64 is String or entry.jpeg_base64.length() > 218456: return false
		else:
			if not _exact(entry, ["entry_id", "sha256", "entry_revision"]) or not _positive_integer(entry.entry_revision): return false
	return true

static func _exact(value: Dictionary, keys: Array) -> bool:
	return value.size() == keys.size() and keys.all(func(key: String) -> bool: return value.has(key))

static func _integer(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= low and value <= high and value == int(value)
