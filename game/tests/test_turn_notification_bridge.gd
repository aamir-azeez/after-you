extends SceneTree
const Bridge = preload("res://services/turn_notification_bridge.gd")

class Native extends Node:
	signal notification_result(id: String, operation: String, payload: String)
	signal notification_error(id: String, operation: String, code: String)
	signal notification_token_changed(payload: String)
	signal notification_received(payload: String)
	var calls := 0
	var invalid := false
	var arguments: Array = []
	func notification_status(id: String) -> void:
		calls += 1
		notification_result.emit(id, "get_token", "{\"wrong_operation\":true}")
		notification_result.emit("unrelated", "status", "{\"wrong_id\":true}")
		if invalid:
			notification_result.emit(id, "status", "[]")
		else:
			notification_result.emit.call_deferred(id, "status", "{\"supported\":false,\"configured\":false}")
	func notification_set_binding(epoch: String, token: String, generation: int, id: String) -> void:
		arguments = [epoch, token, generation]
		notification_result.emit(id, "set_binding", JSON.stringify({"bound": true, "binding_epoch": epoch, "generation": generation}))

var checks := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)

func _run() -> void:
	var native := Native.new()
	root.add_child(native)
	var bridge := Bridge.new()
	bridge._native = native
	root.add_child(bridge)
	var result: Dictionary = await bridge.call_native("status")
	_check(result.get("ok", false) and result.data == {"supported": false, "configured": false}, "Only matching request and operation deliver the deferred native status")
	_check(native.calls == 1, "The wrapper does not retry or duplicate a native call")
	native.invalid = true
	result = await bridge.call_native("status")
	_check(not result.get("ok", false), "A non-object native payload fails closed")
	result = await bridge.call_native("arbitrary_method")
	_check(not result.get("ok", false) and native.calls == 2, "Unknown operations never reach the singleton")
	result = await bridge.call_native("set_binding", ["A".repeat(22), "synthetic-token-000000", 7])
	_check(result.get("ok", false) and native.arguments == ["A".repeat(22), "synthetic-token-000000", 7], "Binding arguments retain the exact epoch/token/generation order")
	var events := [0, 0]
	bridge.token_changed.connect(func(): events[0] += 1)
	bridge.received.connect(func(_value: Dictionary): events[1] += 1)
	native.notification_token_changed.emit("{\"generation\":7,\"registration_pending\":true}")
	native.notification_token_changed.emit("[]")
	native.notification_received.emit("[]")
	native.notification_received.emit("{\"synthetic\":true}")
	_check(events == [1, 1], "Native events are bounded object payloads; coordinator owns strict route validation")
	bridge.free()
	_check(native.get_signal_connection_list("notification_result").is_empty() and native.get_signal_connection_list("notification_received").is_empty(), "Scene cleanup disconnects native callbacks")
	native.free()
	print("TURN NOTIFICATION BRIDGE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
