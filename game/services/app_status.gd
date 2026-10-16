extends Node
## Asks the server whether this build is too old to play online
## (GET /v1/app-status, backend/src/app-status.ts). No player identity is sent.
##
## The answer blocks only when every part of it is well formed and it names a newer
## version for this build's own channel. Any network error, timeout, non-200 status,
## oversized or malformed body, unknown key, other schema, other channel or bad version
## means "no gate" (fail open). The answer lives in memory only: a new launch asks
## again, and an offline launch never blocks.
##
## Runs on its own HTTPRequest, never through RoomsApi, whose single request slot
## belongs to rooms and friends.

signal answered(result: Dictionary)

const ClientIdentity = preload("res://services/client_identity.gd")
const RoomsApi = preload("res://services/rooms_api.gd")
const Save = preload("res://services/local_save.gd")
const PATH := "/v1/app-status"
const TIMEOUT_SECONDS := 8.0
const BODY_LIMIT := 4096
## A resumed app asks again once the last answer is this old.
const RECHECK_SECONDS := 6 * 60 * 60
const OFF := {"gate": "off"}

var base_url := ""
## Whether base_url may be used (RoomsApi.configured()).
var configured := false
var busy := false
var result: Dictionary = OFF.duplicate()
## Wall-clock seconds of the last finished check, or -1 before the first.
var checked_at := -1.0
## Tests replace these: transport(url, headers) -> [result, status, headers, body] or [];
## clock() -> unix seconds.
var transport: Callable
var clock: Callable

func required() -> bool:
	return result.get("gate") == "required"

func now() -> float:
	return float(clock.call()) if clock.is_valid() else Time.get_unix_time_from_system()

## The time since the last check counts on the wall clock, which keeps running while
## the phone sleeps. A clock that went backwards also asks again.
func due() -> bool:
	if checked_at < 0.0: return true
	var elapsed := now() - checked_at
	return elapsed >= RECHECK_SECONDS or elapsed < 0.0

## Asks once and returns the answer. A desktop build (channel "dev") and a build with
## no server never ask. A check already running returns the current answer.
func check() -> Dictionary:
	if busy: return result
	var channel := ClientIdentity.channel()
	var header := ClientIdentity.header_line()
	if not configured or channel == ClientIdentity.DEV or header.is_empty():
		result = OFF.duplicate()
		return result
	busy = true
	var response: Array = await _send(base_url.trim_suffix("/") + PATH, PackedStringArray([header]))
	busy = false
	result = interpret(response, ClientIdentity.version(), channel)
	checked_at = now()
	answered.emit(result)
	return result

func _send(url: String, headers: PackedStringArray) -> Array:
	if transport.is_valid(): return await transport.call(url, headers)
	var request := HTTPRequest.new()
	request.timeout = TIMEOUT_SECONDS
	request.body_size_limit = BODY_LIMIT
	add_child(request)
	if request.request(url, headers, HTTPClient.METHOD_GET) != OK:
		request.queue_free()
		return []
	var response: Array = await request.request_completed
	request.queue_free()
	return response

## {"gate": "required", "min_version", "channel"} only for a complete, valid answer
## that names a newer version for this channel; {"gate": "off"} for everything else.
static func interpret(response: Array, own_version: String, own_channel: String) -> Dictionary:
	if response.size() != 4 or int(response[0]) != HTTPRequest.RESULT_SUCCESS or int(response[1]) != 200: return OFF.duplicate()
	if not response[3] is PackedByteArray or response[3].size() > BODY_LIMIT: return OFF.duplicate()
	var parsed: Variant = JSON.parse_string(response[3].get_string_from_utf8())
	if not parsed is Dictionary or RoomsApi.json_int(parsed.get("schema_version")) != 1: return OFF.duplicate()
	var keys: Array = parsed.keys()
	keys.sort()
	if not Save.equal(parsed.get("gate"), "required") or keys != ["channel", "gate", "min_version", "schema_version"]: return OFF.duplicate()
	var minimum: Variant = parsed.get("min_version")
	if not minimum is String or not Save.equal(parsed.get("channel"), own_channel) or own_channel == ClientIdentity.DEV: return OFF.duplicate()
	var order: Variant = ClientIdentity.compare(own_version, minimum)
	if order == null or int(order) >= 0: return OFF.duplicate()
	return {"gate": "required", "min_version": minimum, "channel": own_channel}
