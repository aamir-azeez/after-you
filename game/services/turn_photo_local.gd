class_name TurnPhotoLocal
extends Node
## Signal-to-request adapter for a dedicated OptionalPhotoCapture node. It never
## starts capture; UI owns the explicit camera action. Returned bytes are local.
signal _done
var _capture: Node
var _busy := false
var _id := ""
var _operation := ""
var _generation := 0
var _result: Dictionary = {}

func migrate_owner(owner: String, store: RefCounted, library: RefCounted, still_current: Callable) -> Dictionary:
	# Best-effort preservation of references present in existing selection/cleanup
	# journals. Missing old cache files cannot be reconstructed. No journal changes
	# or network operations occur here; caller can retry storage failures later.
	if not still_current.is_valid() or not still_current.call():
		return {"ok": false, "error": "identity_changed"}
	var listing: Dictionary = store.list_scopes(owner)
	if not listing.get("ok", false):
		return listing
	var migrated := 0
	var missing := 0
	var failed := 0
	for item: Dictionary in listing.scopes:
		var state: Dictionary = item.value
		var target: Variant = state.get("target")
		if not target is Dictionary or target.get("owner_player_id") != owner:
			failed += 1
			continue
		var ids: Dictionary = {}
		var selection: Variant = state.get("selection", {})
		if selection is Dictionary and selection.get("photo_id") is String:
			ids[selection.photo_id] = true
		var cleanup: Variant = state.get("cleanup", [])
		if cleanup is Array:
			for id: Variant in cleanup:
				if id is String: ids[id] = true
		for id: String in ids:
			if not still_current.call():
				return {"ok": false, "error": "identity_changed", "migrated": migrated, "missing": missing, "failed": failed}
			var read := await request("read", id)
			if not still_current.call():
				return {"ok": false, "error": "identity_changed", "migrated": migrated, "missing": missing, "failed": failed}
			if not read.get("ok", false):
				missing += 1
				continue
			var kept: Dictionary = library.store_local(owner, target, read.get("metadata", {}), read.get("bytes", PackedByteArray()))
			if kept.get("ok", false): migrated += 1
			else: failed += 1
	return {"ok": failed == 0, "migrated": migrated, "missing": missing, "failed": failed}

func _init(capture_wrapper: Node = null) -> void:
	_capture = capture_wrapper

func _ready() -> void:
	if is_instance_valid(_capture):
		_capture.bytes_ready.connect(_bytes)
		_capture.completed.connect(_completed)
		_capture.failed.connect(_failed)

func request(operation: String, photo_id: String) -> Dictionary:
	if _busy or operation not in ["read", "discard"] or not is_instance_valid(_capture) or not is_inside_tree():
		return {"ok": false, "code": "local_photo_unavailable"}
	_busy = true
	_operation = operation
	_result = {}
	var generation := _generation
	_id = _capture.read_photo(photo_id) if operation == "read" else _capture.discard_photo(photo_id)
	# Deferred delivery also handles a synchronous fake/native error arriving
	# before the wrapper's request method returns its unique identifier.
	await _done
	if generation != _generation:
		return {"ok": false, "code": "local_request_invalidated"}
	var result := _result
	_busy = false
	_id = ""
	_operation = ""
	_result = {}
	return result

func invalidate() -> void:
	_generation += 1
	_id = ""
	_operation = ""
	_result = {}
	if _busy:
		_busy = false
		_done.emit()

func _bytes(id: String, metadata: Dictionary, bytes: PackedByteArray) -> void:
	_deliver.call_deferred(id, "read", {"ok": true, "metadata": metadata.duplicate(true), "bytes": bytes.duplicate()}, _generation)

func _completed(id: String, operation: String, acknowledgement: Dictionary) -> void:
	_deliver.call_deferred(id, operation, {"ok": true, "discarded": acknowledgement.get("discarded", false)}, _generation)

func _failed(id: String, operation: String, _code: String) -> void:
	_deliver.call_deferred(id, operation, {"ok": false, "code": "local_photo_unavailable"}, _generation)

func _deliver(id: String, operation: String, value: Dictionary, generation: int) -> void:
	if generation == _generation and _busy and id == _id and operation == _operation and _result.is_empty():
		_result = value
		_done.emit()

func _exit_tree() -> void:
	invalidate()
	if is_instance_valid(_capture):
		for item: Array in [["bytes_ready", _bytes], ["completed", _completed], ["failed", _failed]]:
			if _capture.is_connected(item[0], item[1]):
				_capture.disconnect(item[0], item[1])
