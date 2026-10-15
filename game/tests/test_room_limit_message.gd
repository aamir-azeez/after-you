extends SceneTree
## Hosting or joining at the server's room limit says so, instead of the
## generic "connection was broken" line.
const Api = preload("res://services/rooms_api.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
var checks := 0
var failures := 0

class CapServer extends "res://services/rooms_api.gd":
	func _send(_method: int, _path: String, _headers: PackedStringArray, _body: String) -> Array:
		return [HTTPRequest.RESULT_SUCCESS, 409, PackedStringArray(), JSON.stringify({"error": {"code": "room_limit_reached", "retryable": false}}).to_utf8_buffer()]

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var api := CapServer.new()
	api.base_url = "https://synthetic.invalid"
	root.add_child(api)
	for path: String in ["/v2/rooms", "/v2/rooms/join"]:
		var response: Dictionary = await api.request_json(HTTPClient.METHOD_POST, path, {"idempotency_key": "k"})
		_check(not response.ok and response.code == "room_limit_reached", "The cap refusal reaches the caller: " + path)
		_check(response.error == PlayerCopy.ROOM_LIMIT_REACHED, "The cap refusal names the cap: " + path)
		_check(response.error != Api.error_message("connection_interrupted"), "The cap refusal is not the connection line: " + path)
	api.queue_free()
	print("Room limit message: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
