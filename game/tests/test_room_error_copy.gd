extends SceneTree
## A failed room request says the rehearsal is kept only when a turn was being
## sent. The hub and lobby routes have no rehearsal, so their lines never say so.
const PlayerCopy = preload("res://presentation/player_copy.gd")
var checks := 0
var failures := 0

## Answers every request with `reply`: [] when the request cannot start,
## otherwise [result, status, headers, body].
class ScriptedApi extends "res://services/rooms_api.gd":
	var reply: Array = []
	func _send(_method: int, _path: String, _headers: PackedStringArray, _body: String) -> Array:
		return reply
	func _send_raw(_method: int, _path: String, _headers: PackedStringArray, _body: PackedByteArray) -> Array:
		return reply

const METHOD_NAMES := {HTTPClient.METHOD_GET: "GET", HTTPClient.METHOD_POST: "POST", HTTPClient.METHOD_DELETE: "DELETE"}
const ROOM := "/v2/rooms/AAAAAAAAAAAAAAAAAAAAAA"
const HUB_ROUTES := [
	[HTTPClient.METHOD_GET, "/v2/capabilities"],
	[HTTPClient.METHOD_GET, "/v2/rooms"],
	[HTTPClient.METHOD_POST, "/v2/rooms"],
	[HTTPClient.METHOD_POST, "/v2/rooms/join"],
	[HTTPClient.METHOD_GET, ROOM],
	[HTTPClient.METHOD_DELETE, ROOM],
	[HTTPClient.METHOD_POST, ROOM + "/leave"],
	[HTTPClient.METHOD_GET, "/v1/room-inbox"],
	[HTTPClient.METHOD_POST, "/v1/invitations/resolve"],
	[HTTPClient.METHOD_GET, ROOM + "/turns"],
]
const TURN_ROUTES := [
	[HTTPClient.METHOD_POST, ROOM + "/turns"],
	[HTTPClient.METHOD_POST, "/v1/rooms/AAAAAAAAAAAAAAAAAAAAAA/turns"],
]

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var api := ScriptedApi.new()
	api.base_url = "https://synthetic.invalid"
	root.add_child(api)
	var unknown := [HTTPRequest.RESULT_SUCCESS, 500, PackedStringArray(), JSON.stringify({"error": {"code": "something_new"}}).to_utf8_buffer()]
	var broken := [HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray()]
	for route: Array in HUB_ROUTES + TURN_ROUTES:
		var turn: bool = route in TURN_ROUTES
		var name := "%s %s" % [METHOD_NAMES[route[0]], route[1]]
		for case: Array in [["an unknown server error", unknown, PlayerCopy.ROOMS_API_1C556A121773], ["a broken connection", broken, PlayerCopy.ROOMS_API_1C556A121773], ["a request that never started", [], PlayerCopy.ROOMS_API_7795AD99E31E]]:
			api.reply = case[1]
			var response: Dictionary = await api.request_json(route[0], route[1], {} if route[0] == HTTPClient.METHOD_GET else {"schema_version": 1})
			_said(response, case[2], turn, "%s on %s" % [case[0], name])
		# A request skipped in the queue (its screen closed) reads the same way.
		api.reply = unknown
		var skipped: Dictionary = await api.request_json(route[0], route[1], {}, func() -> bool: return false)
		_said(skipped, PlayerCopy.ROOMS_API_7795AD99E31E, turn, "a skipped request on " + name)
	# Room attempts travel as bytes; their failures follow the same rule.
	api.reply = unknown
	var raw: Dictionary = await api.request_raw(HTTPClient.METHOD_GET, ROOM + "/history/0")
	_said(raw, PlayerCopy.ROOMS_API_1C556A121773, false, "an unknown error on a room attempt read")
	# A server code with its own line keeps that line on every route.
	api.reply = [HTTPRequest.RESULT_SUCCESS, 409, PackedStringArray(), JSON.stringify({"error": {"code": "room_full"}}).to_utf8_buffer()]
	for route: Array in [[HTTPClient.METHOD_POST, "/v2/rooms/join"], TURN_ROUTES[0]]:
		var full: Dictionary = await api.request_json(route[0], route[1], {"schema_version": 1})
		_check(full.error == PlayerCopy.ROOMS_API_5CC5F70801E3, "A known code keeps its own line on " + str(route[1]))
	# Callers that only know the code (the redo clients) get the line alone.
	_check(api.error_message("something_new") == PlayerCopy.ROOMS_API_1C556A121773, "A code without a route gets the line without the rehearsal")
	api.queue_free()
	print("Room error copy: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _said(response: Dictionary, line: String, turn: bool, label: String) -> void:
	var expected := line + " " + PlayerCopy.ROOM_TURN_KEPT if turn else line
	_check(not response.get("ok", true), label + " fails")
	_check(str(response.get("error", "")) == expected, "%s reads \"%s\" (got \"%s\")" % [label, expected, response.get("error", "")])
	if not turn: _check(not str(response.get("error", "")).to_lower().contains("rehearsal"), label + " does not mention a rehearsal")

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
