class_name DeviceSecretStore
extends Node
## Values and result payloads remain local. Do not forward these signals to telemetry.

signal completed(request_id: String, operation: String, payload: Dictionary)
signal failed(request_id: String, operation: String, code: String)

var _native: Object
var _pending: Dictionary = {}

func _ready() -> void:
	_connect_native()

func _connect_native() -> bool:
	if _native != null:
		return true
	if not Engine.has_singleton("AfterYouAndroid"):
		return false
	_native = Engine.get_singleton("AfterYouAndroid")
	_native.connect("secure_result", _on_result)
	_native.connect("secure_error", _on_error)
	return true

func is_available() -> bool:
	return _connect_native()

func put_secret(name: String, value: String) -> String:
	return _request("put", [name, value])

func get_secret(name: String) -> String:
	return _request("get", [name])

func remove_secret(name: String) -> String:
	return _request("remove", [name])

func copy_recovery(player_id: String, recovery_code: String) -> String:
	return _request("copy_recovery", [player_id, recovery_code])

func _request(operation: String, arguments: Array) -> String:
	var id := Crypto.new().generate_random_bytes(16).hex_encode()
	_pending[id] = operation
	if not _connect_native():
		_on_error.call_deferred(id, operation, "android_keystore_unavailable")
		return id
	if not _native.has_method("secure_" + operation):
		_on_error.call_deferred(id, operation, "native_operation_unavailable")
		return id
	arguments.append(id)
	_native.callv("secure_" + operation, arguments)
	return id

func _on_result(id: String, operation: String, payload_json: String) -> void:
	if _pending.get(id, "") != operation:
		return
	var parsed: Variant = JSON.parse_string(payload_json)
	if not parsed is Dictionary:
		_on_error(id, operation, "invalid_storage_response")
		return
	_pending.erase(id)
	completed.emit(id, operation, parsed)

func _on_error(id: String, operation: String, code: String) -> void:
	if _pending.get(id, "") != operation:
		return
	_pending.erase(id)
	failed.emit(id, operation, code)
