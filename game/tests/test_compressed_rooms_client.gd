extends SceneTree
## Compressed rooms on the phone (services/rooms_api.gd, backend src/v2/turn-wire.ts):
## - the capabilities read asks; nothing else does until the server says compressed_rooms_version 1;
## - then a turn goes as the blob of its exact JSON with its length and SHA-256, and room, operation and
##   pair reads ask for compressed replies;
## - a compressed reply is read only when its length and SHA-256 match, the Pollen credit comes from its
##   header, and JSON replies (an older server, errors) read as before;
## - a server that refuses the blob (415 json_required) gets the very same JSON at once, and JSON from then on.
const Api = preload("res://services/rooms_api.gd")
const BlobCodec = preload("res://services/blob_codec.gd")
const ROOM := "RRRRRRRRRRRRRRRRRRRRRR"
var checks := 0
var failures := 0

## Answers from `replies` in turn and keeps what was sent.
class Scripted extends "res://services/rooms_api.gd":
	var replies: Array = []
	var sent: Array = []
	func _send(method: int, path: String, headers: PackedStringArray, body: String) -> Array:
		sent.append({"method": method, "path": path, "headers": headers, "body": body.to_utf8_buffer(), "raw": false})
		return replies.pop_front()
	func _send_raw(method: int, path: String, headers: PackedStringArray, body: PackedByteArray) -> Array:
		sent.append({"method": method, "path": path, "headers": headers, "body": body, "raw": true})
		return replies.pop_front()

func _init() -> void:
	call_deferred("_run")

func _expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

static func _blob_reply(value: Dictionary, extra: PackedStringArray = PackedStringArray()) -> Array:
	var bytes := JSON.stringify(value).to_utf8_buffer()
	var headers := PackedStringArray(["Content-Type: application/octet-stream", "X-AfterYou-Body-Length: %d" % bytes.size(), "X-AfterYou-Body-Digest: " + BlobCodec.digest(bytes)])
	headers.append_array(extra)
	return [HTTPRequest.RESULT_SUCCESS, 200, headers, BlobCodec.encode(bytes)]

static func _json_reply(status: int, value: Dictionary) -> Array:
	return [HTTPRequest.RESULT_SUCCESS, status, PackedStringArray(["Content-Type: application/json"]), JSON.stringify(value).to_utf8_buffer()]

func _api() -> Scripted:
	var api := Scripted.new()
	api.base_url = "https://after-you.test"
	api.player_id = "PPPPPPPPPPPPPPPPPPPPPP"
	api.device_token = "token"
	root.add_child(api)
	return api

func _run() -> void:
	var turns := "/v2/rooms/" + ROOM + "/turns"
	var body := {"base_revision": 3, "idempotency_key": "k".repeat(32), "branch": 0, "recording": {"actions": [{"ticks": 1, "x": 1, "z": -1, "action": true}], "name": "é"}}
	Api.compressed_supported = false
	_expect(Api.capability_headers(HTTPClient.METHOD_GET, "/v2/capabilities").has(Api.COMPRESSED_HEADER), "the capabilities read asks for compressed rooms")
	_expect(not Api.capability_headers(HTTPClient.METHOD_GET, "/v2/rooms/" + ROOM).has(Api.COMPRESSED_HEADER), "no room read asks before the server says so")

	# Off: a turn goes as JSON, as before.
	var api := _api()
	api.replies = [_json_reply(200, {"receipt": {}, "room": {}})]
	var result: Dictionary = await api.request_json(HTTPClient.METHOD_POST, turns, body)
	_expect(result.ok and not api.sent[0].raw and api.sent[0].body == JSON.stringify(body).to_utf8_buffer(), "a turn goes as JSON while the server has not offered compressed rooms")

	# On: the blob of the exact JSON, and a compressed reply read back with its Pollen credit.
	Api.compressed_supported = true
	for path: String in ["/v2/rooms/" + ROOM, "/v2/rooms/" + ROOM + "/operations/" + "k".repeat(32), "/v2/rooms/" + ROOM + "/pairs/p0-1"]:
		_expect(Api.capability_headers(HTTPClient.METHOD_GET, path).has(Api.COMPRESSED_HEADER), "a room, operation and pair read asks for a compressed reply: " + path)
	_expect(not Api.capability_headers(HTTPClient.METHOD_GET, "/v2/rooms/" + ROOM + "/collection").has(Api.COMPRESSED_HEADER), "other reads stay JSON")
	api.sent.clear()
	api.replies = [_blob_reply({"receipt": {"turn_id": "t0-0-a"}, "room": {"revision": 4}}, PackedStringArray(['X-AfterYou-Pollen: {"schema_version":1,"pending":true}']))]
	result = await api.request_json(HTTPClient.METHOD_POST, turns, body)
	var sent: Dictionary = api.sent[0]
	var json := JSON.stringify(body).to_utf8_buffer()
	_expect(sent.raw and sent.headers[0] == "Content-Type: application/octet-stream", "a turn goes as bytes")
	_expect(sent.headers.has("X-AfterYou-Body-Length: %d" % json.size()) and sent.headers.has("X-AfterYou-Body-Digest: " + BlobCodec.digest(json)), "with the JSON's length and SHA-256")
	_expect(BlobCodec.verified(sent.body, json.size(), BlobCodec.digest(json), 1 << 20) == json, "and the blob holds exactly the JSON")
	_expect(result.ok and int(result.data.room.revision) == 4 and result.pollen == {"schema_version": 1.0, "pending": true}, "the compressed reply reads as the JSON one did, Pollen beside it")

	# A compressed reply whose SHA-256 does not match is a broken reply, never a room.
	var bad := _blob_reply({"room": {"revision": 9}})
	bad[2][2] = "X-AfterYou-Body-Digest: " + "0".repeat(64)
	api.replies = [bad]
	result = await api.request_json(HTTPClient.METHOD_GET, "/v2/rooms/" + ROOM)
	_expect(not result.ok and result.data.is_empty(), "a reply that fails its SHA-256 is refused")
	# Errors and an older server's JSON read as before.
	api.replies = [_json_reply(409, {"error": {"code": "stale_revision", "retryable": false}})]
	result = await api.request_json(HTTPClient.METHOD_POST, turns, body)
	_expect(not result.ok and result.code == "stale_revision", "a JSON error reads as before")

	# An older server refuses the blob: the same JSON goes at once, and JSON from then on.
	api.sent.clear()
	api.replies = [_json_reply(415, {"error": {"code": "json_required", "retryable": false}}), _json_reply(200, {"receipt": {}, "room": {"revision": 5}})]
	result = await api.request_json(HTTPClient.METHOD_POST, turns, body)
	_expect(result.ok and api.sent.size() == 2 and api.sent[0].raw and not api.sent[1].raw and api.sent[1].body == json, "a refused blob goes again as the same JSON")
	_expect(not api.sent[1].headers.has(Api.COMPRESSED_HEADER) and not Api.compressed_supported, "and the phone sends JSON from then on")
	Api.compressed_supported = false
	api.queue_free()
	print("COMPRESSED ROOMS CLIENT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
