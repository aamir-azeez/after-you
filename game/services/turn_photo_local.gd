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
