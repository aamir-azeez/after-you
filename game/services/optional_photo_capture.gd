class_name OptionalPhotoCapture
extends Node
## Optional local capture only; no identity, gameplay, upload or analytics dependencies.
## Metadata is separate from explicit byte reads. Never log bytes_ready payloads.

signal kept(request_id: String, metadata: Dictionary)
signal skipped(request_id: String)
signal bytes_ready(request_id: String, metadata: Dictionary, bytes: PackedByteArray)
signal completed(request_id: String, operation: String, acknowledgement: Dictionary)
signal failed(request_id: String, operation: String, code: String)

const MAX_BYTES := 160 * 1024
const MAX_EDGE := 960
const AUXILIARY_TIMEOUT_MS := 15000
const META_KEYS := ["status", "photo_id", "mime", "width", "height", "byte_count", "sha256", "metadata_removed", "uploaded"]
const SAFE_ERRORS := ["activity_unavailable", "photo_unavailable", "photo_busy", "camera_unavailable", "invalid_photo_id", "photo_cancelled", "photo_cleanup_unavailable"]
var _native: Object
var _bridge_ready := false
var _prefix := Crypto.new().generate_random_bytes(16).hex_encode()
var _sequence := 0
var _generation := 0
var _pending: Dictionary = {}
var _capture_id := ""
var _cancel_requested := false
var _known: Dictionary = {}

func _init(native_override: Object = null) -> void:
	_native = native_override

func _ready() -> void:
	set_process(false)
	_connect_native() # Registers observers only; never opens the camera.

func _connect_native() -> bool:
	if not is_instance_valid(_native):
		if not Engine.has_singleton("AfterYouAndroid"):
			return false
		_native = Engine.get_singleton("AfterYouAndroid")
	# Signals are registered Godot signals. Old plugins lack these and expose
	# unavailable; has_method cannot discover the Java JNI dynamic method map.
	if not _native.has_signal("photo_result") or not _native.has_signal("photo_error"):
		_bridge_ready = false
		return false
	if not _native.is_connected("photo_result", _on_result):
		_native.connect("photo_result", _on_result)
	if not _native.is_connected("photo_error", _on_error):
		_native.connect("photo_error", _on_error)
	_bridge_ready = true
	return true

func is_available() -> bool:
	return _connect_native()

func is_busy() -> bool:
	return not _pending.is_empty()

func capture() -> String:
	if is_busy():
		return _reject("capture", "photo_busy")
	return _request("capture")

func cancel_capture() -> String:
	if _capture_id.is_empty():
		return _reject("cancel", "no_active_capture")
	if _cancel_requested:
		return _reject("cancel", "photo_busy")
	_cancel_requested = true
	return _request("cancel", _capture_id)

func read_photo(photo_id: String) -> String:
	return _file_request("read", photo_id)

func discard_photo(photo_id: String) -> String:
	return _file_request("discard", photo_id)

func clear_photos() -> String:
	# Explicit confirmed-account-deletion cleanup. Ordinary invalidate/sign-out never calls this.
	if _pending.values().any(func(item: Dictionary) -> bool: return item.operation == "clear"):
		return _reject("clear", "photo_busy")
	var retired := _pending.duplicate(true)
	invalidate() # Stale results cannot expose pixels or revive selections while native cleanup runs.
	var id := _request("clear")
	_retire_for_clear.call_deferred(retired, _generation)
	return id

func _retire_for_clear(retired: Dictionary, generation: int) -> void:
	if generation != _generation:
		return
	for id: String in retired:
		if retired[id].operation == "capture":
			skipped.emit(id)
		else:
			failed.emit(id, retired[id].operation, "photo_cancelled")

func _file_request(operation: String, photo_id: String) -> String:
	if not _matches(photo_id, "^[a-f0-9]{32}$"):
		return _reject(operation, "invalid_photo_id")
	if is_busy():
		return _reject(operation, "photo_busy")
	return _request(operation, photo_id)

func _next_id() -> String:
	_sequence += 1
	return _prefix + "-" + str(_sequence)

func _reject(operation: String, code: String) -> String:
	var id := _next_id()
	_emit_rejection.call_deferred(id, operation, code, _generation)
	return id

func _emit_rejection(id: String, operation: String, code: String, generation: int) -> void:
	if generation == _generation:
		failed.emit(id, operation, code)

func _request(operation: String, target: String = "") -> String:
	var id := _next_id()
	_pending[id] = {"operation": operation, "target": target, "deadline": 0 if operation == "capture" else Time.get_ticks_msec() + AUXILIARY_TIMEOUT_MS}
	if operation == "capture":
		_capture_id = id
		_cancel_requested = false
	set_process(operation != "capture")
	if not _connect_native():
		_on_error.call_deferred(id, operation, "photo_bridge_unavailable")
		return id
	_native.callv("photo_" + operation, [id] if operation in ["capture", "clear"] else [target, id])
	return id

func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	for id: String in _pending.keys():
		var item: Dictionary = _pending[id]
		if item.deadline > 0 and now >= int(item.deadline):
			_finish_error(id, item.operation, "photo_request_timeout")

func _forget(id: String) -> void:
	_pending.erase(id)
	if id == _capture_id:
		_capture_id = ""
		_cancel_requested = false
	set_process(_pending.values().any(func(item: Dictionary) -> bool: return item.deadline > 0))

func _on_result(id: String, operation: String, payload_json: String) -> void:
	if _pending.get(id, {}).get("operation", "") != operation:
		return
	var limit := 224 * 1024 if operation == "read" else 2048
	if payload_json.length() > limit or payload_json.to_utf8_buffer().size() > limit:
		_finish_error(id, operation, "invalid_photo_response")
		return
	var parsed: Variant = JSON.parse_string(payload_json)
	if not parsed is Dictionary:
		_finish_error(id, operation, "invalid_photo_response")
		return
	var target: String = _pending[id].target
	if operation == "capture":
		if _keys(parsed, ["status", "uploaded"]) and parsed.status == "skipped" and parsed.uploaded is bool and parsed.uploaded == false:
			_forget(id)
			skipped.emit(id)
		elif _metadata_valid(parsed):
			var cancelled := _cancel_requested
			_forget(id)
			if cancelled:
				# Cancellation may race an already-kept callback. Do not surface the
				# selection; best-effort discard this exact new local cache entry.
				_native.callv("photo_discard", [parsed.photo_id, _next_id()])
				skipped.emit(id)
			else:
				if _known.size() >= 16:
					_known.erase(_known.keys()[0])
				_known[parsed.photo_id] = parsed.duplicate(true)
				kept.emit(id, parsed.duplicate(true))
		else:
			_finish_error(id, operation, "invalid_photo_response")
	elif operation == "read":
		if not _keys(parsed, META_KEYS + ["jpeg_base64"]) or not parsed.jpeg_base64 is String:
			_finish_error(id, operation, "invalid_photo_response")
			return
		var metadata: Dictionary = parsed.duplicate(true)
		metadata.erase("jpeg_base64")
		if not _metadata_valid(metadata) or metadata.photo_id != target or (_known.has(target) and _known[target] != metadata):
			_finish_error(id, operation, "invalid_photo_response")
			return
		var encoded: String = parsed.jpeg_base64
		if encoded.length() > ceili(float(MAX_BYTES) / 3.0) * 4 or not _matches(encoded, "^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$"):
			_finish_error(id, operation, "invalid_photo_response")
			return
		var bytes := Marshalls.base64_to_raw(encoded)
		var hash := HashingContext.new()
		hash.start(HashingContext.HASH_SHA256)
		hash.update(bytes)
		if bytes.size() != int(metadata.byte_count) or Marshalls.raw_to_base64(bytes) != encoded or hash.finish().hex_encode() != metadata.sha256:
			_finish_error(id, operation, "invalid_photo_response")
			return
		_forget(id)
		bytes_ready.emit(id, metadata, bytes)
	elif operation == "clear":
		if not _keys(parsed, ["cleared"]) or not parsed.cleared is bool or parsed.cleared != true:
			_finish_error(id, operation, "invalid_photo_response")
			return
		_forget(id)
		_known.clear()
		completed.emit(id, operation, {"cleared": true})
	elif operation in ["cancel", "discard"]:
		var key := "cancelled" if operation == "cancel" else "discarded"
		if not _keys(parsed, [key]) or not parsed[key] is bool:
			_finish_error(id, operation, "invalid_photo_response")
			return
		_forget(id)
		if operation == "discard" and parsed.discarded:
			_known.erase(target)
		if operation == "cancel" and parsed.cancelled and _pending.get(target, {}).get("operation") == "capture":
			_forget(target)
			skipped.emit(target)
		elif operation == "cancel" and not parsed.cancelled:
			_cancel_requested = false
		completed.emit(id, operation, parsed)

func _on_error(id: String, operation: String, code: String) -> void:
	var safe := code if code in SAFE_ERRORS or code == "photo_bridge_unavailable" else "photo_unavailable"
	_finish_error(id, operation, safe)

func _finish_error(id: String, operation: String, code: String) -> void:
	if _pending.get(id, {}).get("operation", "") != operation:
		return
	if operation == "cancel":
		_cancel_requested = false
	_forget(id)
	failed.emit(id, operation, code)

func invalidate() -> void:
	# Owning scene/account changes must call this before releasing the wrapper.
	# Old callbacks cannot revive selections or local byte reads. Native cache
	# cleanup remains best-effort; no deletion or upload of gameplay data occurs.
	var old_capture := _capture_id
	_generation += 1
	_pending.clear()
	_known.clear()
	_capture_id = ""
	_cancel_requested = false
	set_process(false)
	if not old_capture.is_empty() and _bridge_ready and is_instance_valid(_native):
		_native.callv("photo_cancel", [old_capture, _next_id()])

func _exit_tree() -> void:
	invalidate()
	if is_instance_valid(_native):
		if _native.has_signal("photo_result") and _native.is_connected("photo_result", _on_result):
			_native.disconnect("photo_result", _on_result)
		if _native.has_signal("photo_error") and _native.is_connected("photo_error", _on_error):
			_native.disconnect("photo_error", _on_error)

static func _metadata_valid(value: Dictionary) -> bool:
	return _keys(value, META_KEYS) and value.status == "kept" and value.mime == "image/jpeg" and value.metadata_removed is bool and value.metadata_removed == true and value.uploaded is bool and value.uploaded == false and _matches(value.photo_id, "^[a-f0-9]{32}$") and _matches(value.sha256, "^[a-f0-9]{64}$") and _integer(value.width, MAX_EDGE) and _integer(value.height, MAX_EDGE) and _integer(value.byte_count, MAX_BYTES)

static func _integer(value: Variant, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= 1 and value <= maximum and value == int(value)

static func _matches(value: Variant, pattern: String) -> bool:
	if not value is String:
		return false
	var expression := RegEx.new()
	expression.compile(pattern)
	var found := expression.search(value)
	return found != null and found.get_string() == value

static func _keys(value: Dictionary, keys: Array) -> bool:
	return value.size() == keys.size() and keys.all(func(key: String) -> bool: return value.has(key))
