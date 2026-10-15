extends "res://services/rooms_api.gd"
## One device's RoomsApi for the online scenario harness. Everything the app
## does (the request queue, capability headers, credentials, JSON parsing, error
## copy) runs unchanged; only the HTTP exchange goes to the shared FakeServer.
## The request reaches the server after `latency_frames` frames and the reply
## arrives the same number of frames later, so requests from both devices
## interleave the way they do on phones.
##
## Frames come from this node's own _process. Freeing the device (a force
## quit) drops every exchange in flight without resuming any caller.
signal _pulse
signal _release

var server: RefCounted
var device := ""
var latency_frames := 2
## 0.6.0 sent fewer capability headers; see FakeServer for what that changes.
var legacy_060 := false
var offline := false
## Queued faults, matched in order: {"path": prefix or "", "method": -1 or
## HTTPClient.METHOD_*, "kind": "drop_before" | "drop_after" | "hold" | "status",
## "status": int, "code": String, "count": int}
var faults: Array[Dictionary] = []
var held := 0
var requests: Array[Dictionary] = []
## Idempotency keys of writes whose reply reached this phone, and any such
## write sent again: the request queue must never repeat a write.
var _answered_keys: Dictionary = {}
var repeated_keys: Array[String] = []
var frame := 0

func _ready() -> void:
	base_url = "https://harness.invalid"

func configured() -> bool:
	return true

func _process(_delta: float) -> void:
	frame += 1
	_pulse.emit()

func release_held() -> void:
	_release.emit()

func _wait(frames: int) -> void:
	for i in frames: await _pulse

func _take_fault(method: int, path: String) -> Dictionary:
	for index in faults.size():
		var fault: Dictionary = faults[index]
		if int(fault.get("method", -1)) not in [-1, method]: continue
		if not path.begins_with(str(fault.get("path", ""))): continue
		var left := int(fault.get("count", 1)) - 1
		if left <= 0: faults.remove_at(index)
		else: fault.count = left
		return fault
	return {}

func _send(method: int, path: String, headers: PackedStringArray, body: String) -> Array:
	var fault := _take_fault(method, path)
	var entry := {"device": device, "method": method, "path": path, "frame": frame, "status": 0, "code": "", "fault": str(fault.get("kind", ""))}
	requests.append(entry)
	await _wait(latency_frames)
	if offline or fault.get("kind") == "drop_before":
		entry.code = "offline" if offline else "dropped"
		return [HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray()]
	if fault.get("kind") == "hold":
		held += 1
		await _release
		held -= 1
	var sent: PackedStringArray = headers
	if legacy_060: sent = server.legacy_headers(headers)
	var parsed: Variant = JSON.parse_string(body) if not body.is_empty() else {}
	var key := str(parsed.get("idempotency_key", "")) if method != HTTPClient.METHOD_GET and parsed is Dictionary else ""
	if not key.is_empty() and _answered_keys.has(path + " " + key): repeated_keys.append(path + " " + key.left(6))
	var reply: Dictionary
	if fault.get("kind") == "status":
		reply = {"status": int(fault.get("status", 503)), "body": {"error": {"code": str(fault.get("code", "unavailable")), "retryable": true}}, "headers": PackedStringArray(fault.get("headers", PackedStringArray()))}
	else:
		reply = server.handle(method, path, sent, parsed if parsed is Dictionary else {})
	entry.status = int(reply.status)
	var error: Variant = reply.body.get("error") if reply.body is Dictionary else null
	entry.code = str(error.get("code", "")) if error is Dictionary else ""
	await _wait(latency_frames)
	if fault.get("kind") == "drop_after":
		entry.code = "reply_lost"
		return [HTTPRequest.RESULT_TIMEOUT, 0, PackedStringArray(), PackedByteArray()]
	if not key.is_empty() and int(reply.status) >= 200 and int(reply.status) < 300: _answered_keys[path + " " + key] = true
	return [HTTPRequest.RESULT_SUCCESS, int(reply.status), PackedStringArray(reply.get("headers", PackedStringArray())), JSON.stringify(reply.body).to_utf8_buffer()]

## Byte bodies and replies (room attempts) take the same path and faults.
func _send_raw(method: int, path: String, headers: PackedStringArray, body: PackedByteArray) -> Array:
	var fault := _take_fault(method, path)
	var entry := {"device": device, "method": method, "path": path, "frame": frame, "status": 0, "code": "", "fault": str(fault.get("kind", ""))}
	requests.append(entry)
	await _wait(latency_frames)
	if offline or fault.get("kind") == "drop_before":
		entry.code = "offline" if offline else "dropped"
		return [HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray()]
	if fault.get("kind") == "hold":
		held += 1
		await _release
		held -= 1
	var sent: PackedStringArray = headers
	if legacy_060: sent = server.legacy_headers(headers)
	var reply: Dictionary
	if fault.get("kind") == "status":
		reply = {"status": int(fault.get("status", 503)), "body": {"error": {"code": str(fault.get("code", "unavailable")), "retryable": true}}, "headers": PackedStringArray()}
	else:
		reply = server.handle_raw(method, path, sent, body)
	entry.status = int(reply.status)
	var error: Variant = reply.body.get("error") if reply.body is Dictionary else null
	entry.code = str(error.get("code", "")) if error is Dictionary else ""
	await _wait(latency_frames)
	if fault.get("kind") == "drop_after":
		entry.code = "reply_lost"
		return [HTTPRequest.RESULT_TIMEOUT, 0, PackedStringArray(), PackedByteArray()]
	var bytes: PackedByteArray = reply.bytes if reply.has("bytes") else JSON.stringify(reply.body).to_utf8_buffer()
	return [HTTPRequest.RESULT_SUCCESS, int(reply.status), PackedStringArray(reply.get("headers", PackedStringArray())), bytes]
