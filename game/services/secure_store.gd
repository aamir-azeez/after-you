class_name DeviceSecretStore
extends Node
## Values and result payloads remain local. Do not forward these signals to telemetry.
## Android Keystore or the iOS Keychain, through the shared native plugin lookup.
const NativeBridge = preload("res://services/native_bridge.gd")

signal completed(request_id: String, operation: String, payload: Dictionary)
signal failed(request_id: String, operation: String, code: String)

var _native: Object
var _pending: Dictionary = {}
var _deadlines: Dictionary = {}
const REQUEST_TIMEOUT_MS := 9000
## The screen lock check waits for the player to type a PIN or touch the sensor.
const CONFIRM_TIMEOUT_MS := 300000

func _ready() -> void:
	set_process(false)
	_connect_native()

func _connect_native() -> bool:
	if _native != null:
		return true
	_native = NativeBridge.singleton("secure_store")
	if _native == null:
		return false
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

## The recovery code's guards (services/recovery_guard.gd uses them). A build whose plugin
## lacks them (iOS for now, desktop) has no screen lock check and no private screen.
func device_check_supported() -> bool:
	return _connect_native() and NativeBridge.has_method_on(_native, "secure_confirm_device")

## The phone's screen lock: {"confirmed": true, "locked": bool}, or an error when the player
## cancels. A phone with no screen lock answers confirmed with "locked": false.
func confirm_device() -> String:
	return _request("confirm_device", [], CONFIRM_TIMEOUT_MS)

## Blocks screenshots and the app switcher's picture while recovery details show.
func set_private_screen(on: bool) -> void:
	if _connect_native() and NativeBridge.has_method_on(_native, "secure_private_screen"):
		_native.callv("secure_private_screen", [on])

## After a paste import: takes the details off the clipboard when they are still there.
func clear_recovery_clip(recovery_code: String) -> void:
	if _connect_native() and NativeBridge.has_method_on(_native, "secure_clear_recovery_clip"):
		_native.callv("secure_clear_recovery_clip", [recovery_code])

func _request(operation: String, arguments: Array, timeout_ms: int = REQUEST_TIMEOUT_MS) -> String:
	var id := Crypto.new().generate_random_bytes(16).hex_encode()
	_pending[id] = operation
	_deadlines[id] = Time.get_ticks_msec() + timeout_ms
	set_process(true)
	if not _connect_native():
		_on_error.call_deferred(id, operation, "android_keystore_unavailable")
		return id
	arguments.append(id)
	# Android JNISingleton methods dispatch dynamically through callv; Object.has_method
	# does not inspect their Java method map. The plugin and wrapper ship together.
	_native.callv("secure_" + operation, arguments)
	return id

func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	for id in _pending.keys():
		if now >= int(_deadlines.get(id, now + REQUEST_TIMEOUT_MS)):
			_on_error(id, str(_pending[id]), "native_request_timeout")

func _forget_request(id: String) -> void:
	_pending.erase(id)
	_deadlines.erase(id)
	if _pending.is_empty():
		set_process(false)

func _on_result(id: String, operation: String, payload_json: String) -> void:
	if _pending.get(id, "") != operation:
		return
	var parsed: Variant = JSON.parse_string(payload_json)
	if not parsed is Dictionary:
		_on_error(id, operation, "invalid_storage_response")
		return
	_forget_request(id)
	completed.emit(id, operation, parsed)

func _on_error(id: String, operation: String, code: String) -> void:
	if _pending.get(id, "") != operation:
		return
	_forget_request(id)
	failed.emit(id, operation, code)
