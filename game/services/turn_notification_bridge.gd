extends Node
## Optional native bridge. Tokens and route payloads are never logged.
signal token_changed
signal received(route: Dictionary)

var _native: Object
var _connected := false
var _pending: Dictionary = {}
var _results: Dictionary = {}

func _connect_native() -> bool:
	if _connected: return true
	if _native == null:
		if not Engine.has_singleton("AfterYouAndroid"): return false
		_native = Engine.get_singleton("AfterYouAndroid")
	for name: String in ["notification_result", "notification_error", "notification_token_changed", "notification_received"]:
		if not _native.has_signal(name): return false
	_native.connect("notification_result", _on_result)
	_native.connect("notification_error", _on_error)
	_native.connect("notification_token_changed", _on_token_changed)
	_native.connect("notification_received", _on_received)
	_connected = true
	return true

func call_native(operation: String, arguments: Array = []) -> Dictionary:
	if operation not in ["status", "request_permission", "get_token", "set_binding", "clear_binding", "pending_route", "ack_route", "disable"]:
		return {"ok": false, "code": "unsupported_operation"}
	if not _connect_native(): return {"ok": false, "code": "notifications_unavailable"}
	var id := Crypto.new().generate_random_bytes(16).hex_encode()
	_pending[id] = operation
	var args := arguments.duplicate()
	args.append(id)
	# JNI singleton methods dispatch through callv, not Object.has_method.
	_native.callv("notification_" + operation, args)
	var deadline := Time.get_ticks_msec() + (100000 if operation == "request_permission" else 10000)
	while not _results.has(id) and is_inside_tree() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var result: Dictionary = _results.get(id, {"ok": false, "code": "notification_timeout"})
	_pending.erase(id)
	_results.erase(id)
	return result

func _on_result(id: String, operation: String, payload_json: String) -> void:
	if _pending.get(id) != operation or _results.has(id): return
	if payload_json.length() > 16384:
		_on_error(id, operation, "invalid_notification_response")
		return
	var parsed: Variant = JSON.parse_string(payload_json)
	_results[id] = {"ok": true, "data": parsed} if parsed is Dictionary else {"ok": false, "code": "invalid_notification_response"}

func _on_error(id: String, operation: String, _code: String) -> void:
	if _pending.get(id) == operation and not _results.has(id):
		_results[id] = {"ok": false, "code": "notification_unavailable"}

func _on_token_changed(payload_json: String) -> void:
	if payload_json.length() > 256: return
	var data: Variant = JSON.parse_string(payload_json)
	if data is Dictionary and data.get("registration_pending") == true:
		token_changed.emit()

func _on_received(payload_json: String) -> void:
	if payload_json.length() > 2048: return
	var data: Variant = JSON.parse_string(payload_json)
	if data is Dictionary: received.emit(data)

func _exit_tree() -> void:
	if not _connected or not is_instance_valid(_native): return
	for entry: Array in [["notification_result", _on_result], ["notification_error", _on_error], ["notification_token_changed", _on_token_changed], ["notification_received", _on_received]]:
		if _native.is_connected(entry[0], entry[1]): _native.disconnect(entry[0], entry[1])
	_connected = false
