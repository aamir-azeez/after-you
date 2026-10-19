extends Node
const PlayerCopy = preload("res://presentation/player_copy.gd")
const ClientIdentity = preload("res://services/client_identity.gd")
const RequestQueue = preload("res://services/request_queue.gd")
const Typed = preload("res://services/typed_values.gd")
const DisplayNames = preload("res://services/display_names.gd")
## One bounded request at a time, in the order asked (services/request_queue.gd).
## Callers retain draft/idempotency state.
const MAX_RESPONSE_BYTES := 4194304
## The completed replay-transfer download carries its whole archive inline: at
## most the server's MAX_REPLAY_ARCHIVE_BYTES (16 MiB) plus a manifest of about
## 42 KB at its widest. Every other response keeps the 4 MiB cap.
const MAX_REPLAY_TRANSFER_RESPONSE_BYTES := 16 * 1024 * 1024 + 65536
## One room attempt as the server sends it: an encoding byte and at most 4 MiB.
const MAX_HISTORY_RESPONSE_BYTES := 4 * 1024 * 1024 + 65536
## True once this phone has shown it can keep room attempts durably and byte for
## byte (the history store's startup check). Every /v2 request then says so, and
## only then may the server let a room's finished attempts leave it.
static var history_supported := false
const END_REACTIONS_HEADER := "X-AfterYou-End-Reactions: 1"
var base_url := ""
var player_id := ""
var device_token := ""
var _queue := RequestQueue.new()
## A request came back 426 client_update_required (a route that refuses this build).
signal update_required

func configured() -> bool:
	return base_url.begins_with("https://") or (OS.has_feature("debug") and base_url.begins_with("http://127.0.0.1:"))

## Every request takes its turn in the one queue. `still`, when given, is the
## caller's check of its own screen or state: a request whose turn comes after
## it fails is skipped with "request_cancelled".
func request_json(method: int, path: String, body: Dictionary={}, still: Callable = Callable()) -> Dictionary:
	return await _request_json(method,path,body,PackedStringArray(),still)

## One request with extra headers after the capability ones (the iOS registration's platform headers).
func request_json_with_headers(method: int, path: String, body: Dictionary, extra: PackedStringArray, still: Callable = Callable()) -> Dictionary:
	return await _request_json(method,path,body,extra,still)

func _request_json(method: int, path: String, body: Dictionary, extra: PackedStringArray, still: Callable) -> Dictionary:
	if not configured():
		return {"ok":false,"status":0,"error":PlayerCopy.ROOMS_API_12A6D5364AAB}
	var headers := capability_headers(method,path)
	headers.append_array(extra)
	_append_credentials(headers)
	var payload := "" if method==HTTPClient.METHOD_GET else JSON.stringify(body)
	return await _queue.run(func() -> Dictionary: return _result(await _send(method,path,headers,payload),method,path),
		_refused.bind(method,path),_same_identity(still),_read_key(method,path,headers))

## One request whose body and reply are bytes (room attempts), never parsed as JSON
## when they succeed. Same headers, queue and error shape as the JSON path.
func request_raw(method: int, path: String, body: PackedByteArray = PackedByteArray(), still: Callable = Callable()) -> Dictionary:
	if not configured():
		return {"ok":false,"status":0,"error":PlayerCopy.ROOMS_API_12A6D5364AAB}
	var headers := capability_headers(method,path)
	if method != HTTPClient.METHOD_GET: headers[0] = "Content-Type: application/octet-stream"
	_append_credentials(headers)
	return await _queue.run(func() -> Dictionary: return _raw_result(method,path,await _send_raw(method,path,headers,body)),
		_refused.bind(method,path),_same_identity(still),_read_key(method,path,headers,"raw"))

## Credentials are read when the request is asked for, never when its turn comes.
func _append_credentials(headers: PackedStringArray) -> void:
	if not device_token.is_empty():
		headers.append("Authorization: Bearer "+device_token)
		headers.append("X-Player-Id: "+player_id)

## A request asked for under one identity never goes out under another: a
## recovery, deletion or new identity while it waits skips it.
func _same_identity(still: Callable) -> Callable:
	var asked_player := player_id
	var asked_token := device_token
	return func() -> bool: return player_id == asked_player and device_token == asked_token and (still.is_null() or (still.is_valid() and still.call()))

## Reads that would send the very same request share one turn; writes never do.
static func _read_key(method: int, path: String, headers: PackedStringArray, kind: String = "json") -> String:
	if method != HTTPClient.METHOD_GET: return ""
	return kind+" "+path+"
"+"
".join(headers)

static func _refused(code: String, method: int = HTTPClient.METHOD_GET, path: String = "") -> Dictionary:
	var full := code == RequestQueue.FULL
	return {"ok":false,"status":0,"code":code,"cancelled":code == RequestQueue.CANCELLED,"retryable":true,"retry_after_ms":0,
		"error":PlayerCopy.ROOMS_API_DA75E6F7A674 if full else for_route(PlayerCopy.ROOMS_API_7795AD99E31E,method,path)}

func _raw_result(method: int, path: String, response: Array) -> Dictionary:
	var result := _result(response,method,path)
	if not response.is_empty():
		var status := int(response[1])
		result["bytes"] = response[3] if status >= 200 and status < 300 else PackedByteArray()
		if response[0]==HTTPRequest.RESULT_SUCCESS and status>=200 and status<300 and method == HTTPClient.METHOD_GET: result["ok"] = true
	return result

func _result(response: Array, method: int = HTTPClient.METHOD_GET, path: String = "") -> Dictionary:
	if response.is_empty():
		return {"ok":false,"status":0,"error":for_route(PlayerCopy.ROOMS_API_7795AD99E31E,method,path)}
	var parser := JSON.new()
	var parsed: Variant=parser.data if parser.parse(response[3].get_string_from_utf8())==OK else null
	var payload: Dictionary=parsed if parsed is Dictionary else {}
	var status := int(response[1])
	var server_error: Variant=payload.get("error",{})
	var code := str(server_error.get("code","connection_interrupted")) if server_error is Dictionary else "connection_interrupted"
	# A route refusing this build as too old: the app asks /v1/app-status again.
	if status==426 and code=="client_update_required": update_required.emit()
	var result := {"ok":response[0]==HTTPRequest.RESULT_SUCCESS and status>=200 and status<300 and parsed is Dictionary,"status":status,"data":payload,"error":error_message(code,method,path),"code":code,"retry_after_ms":retry_after_ms(response[2]),"retryable":bool(server_error.get("retryable",true)) if server_error is Dictionary else true}
	# A room's end reactions ride beside its read or turn reply. They leave the
	# reply here, so the room that is checked and kept is exactly what it was.
	if payload.has("end_reactions"):
		result["end_reactions"] = payload["end_reactions"]
		payload.erase("end_reactions")
	# So does the room partner's display name (services/display_names.gd).
	if payload.has("partner_name"):
		result["partner_name"] = payload["partner_name"]
		payload.erase("partner_name")
	return result

## One HTTP exchange: [result, status, headers, body] as HTTPRequest reports
## it, or [] when the request could not start. Test transports override this.
func _send(method: int, path: String, headers: PackedStringArray, body: String) -> Array:
	var request := HTTPRequest.new()
	request.timeout=20.0
	request.body_size_limit=response_limit(method,path)
	add_child(request)
	if request.request(base_url.trim_suffix("/")+path,headers,method,body)!=OK:
		request.queue_free()
		return []
	var response: Array=await request.request_completed
	request.queue_free()
	return response

## The same exchange with a byte body. Test transports override this too.
func _send_raw(method: int, path: String, headers: PackedStringArray, body: PackedByteArray) -> Array:
	var request := HTTPRequest.new()
	request.timeout=20.0
	request.body_size_limit=response_limit(method,path)
	add_child(request)
	if request.request_raw(base_url.trim_suffix("/")+path,headers,method,body)!=OK:
		request.queue_free()
		return []
	var response: Array=await request.request_completed
	request.queue_free()
	return response

## Server replies come from Godot's JSON parser, where every number is a float
## (2.0): `2.0 in [1,2]` is false, `2.0 is int` is false and str(4.0) is "4.0".
## The whole number a parsed JSON value holds, or `fallback` when it holds none.
static func json_int(value: Variant, fallback: int = -1) -> int:
	return Typed.as_int(value, fallback)

## The capability headers this build sends for one request (no credentials).
static func capability_headers(method: int, path: String) -> PackedStringArray:
	var headers := PackedStringArray(["Content-Type: application/json"])
	# Room level 2: this build plays chapters with more than two stages, so the
	# server may list them and accept a longer join list. Older servers ignore it.
	if path == "/v2/capabilities": headers.append("X-AfterYou-Room-Level: 2")
	# This build can hold the live socket (services/live_connection.gd), so the server may offer it.
	if path == "/v2/capabilities": headers.append("X-AfterYou-Live: 1")
	# This build sends and reads turn try counts (services/turn_tries.gd).
	if path == "/v2/capabilities": headers.append("X-AfterYou-Turn-Tries: 1")
	# This build sends and shows end-of-run reactions (services/end_reaction_store.gd):
	# the capability, a room's faces beside its reads and turn replies, and the
	# friend's face in the room list. rooms_api takes the faces out of the reply.
	if end_reaction_path(method, path): headers.append(END_REACTIONS_HEADER)
	# This build shows display names (services/display_names.gd): the capability,
	# a room partner's name beside the same room reads, turn replies and the room
	# list, and friends' names on the friends list. The partner's name leaves the
	# room reply here too.
	if end_reaction_path(method, path) or (method == HTTPClient.METHOD_GET and path == "/v1/friends"): headers.append(DisplayNames.HEADER)
	# This build plays hard rooms (services/hard_mode.gd): it may be told of them and join one.
	if path in ["/v2/capabilities", "/v2/rooms/join"]: headers.append("X-AfterYou-Hard-Mode: 1")
	# The inbox then reports a room another member closed as "closed".
	if path == "/v1/room-inbox": headers.append("X-AfterYou-Room-Inbox: 2")
	# A finished room the other member left then says so (partner_left), for Leave room's confirm step.
	if path == "/v1/room-inbox": headers.append("X-AfterYou-Room-Leave: 1")
	# The friends list may then include the player's short name (friend_alias).
	if method == HTTPClient.METHOD_GET and path == "/v1/friends": headers.append("X-AfterYou-Friends: 2")
	# A finished room whose replay moved to the phones reads as finished here.
	if method == HTTPClient.METHOD_GET and path.begins_with("/v2/rooms/") and path.count("/") == 3: headers.append("X-AfterYou-Finished-Room: 2")
	# Closing a room only ever ends one still in play, never one that just finished.
	if method == HTTPClient.METHOD_DELETE and path.begins_with("/v") and path.count("/") == 3 and path.contains("/rooms/"): headers.append("X-AfterYou-Close-If: in-play")
	# This build reads hosting events, so the server may list them and push them
	# to this phone. Builds up to 0.6.0 rejected them and never get them.
	if path in ["/v1/social/inbox","/v1/notifications/registration"]: headers.append("X-AfterYou-Friend-Events: 2")
	# This phone keeps room attempts durably, so a finished attempt may leave the server.
	if history_supported and path.begins_with("/v2/"): headers.append("X-AfterYou-History: 1")
	# This build's version and channel, so the server can ask an old build to update.
	var client := ClientIdentity.header_line()
	if not client.is_empty(): headers.append(client)
	return headers

## The requests that ask for end reactions: the capability, a room's read, its
## turns and the room list.
static func end_reaction_path(method: int, path: String) -> bool:
	if path in ["/v2/capabilities", "/v1/room-inbox"]: return true
	if not path.begins_with("/v2/rooms/"): return false
	var parts := path.split("/")
	if parts.size() == 4: return method == HTTPClient.METHOD_GET and parts[3].length() == 22
	return parts.size() == 5 and method == HTTPClient.METHOD_POST and parts[3].length() == 22 and parts[4] == "turns"

static func response_limit(method: int, path: String) -> int:
	if method == HTTPClient.METHOD_GET and RegEx.create_from_string("^/v2/rooms/[A-Za-z0-9_-]{22}/replay-transfer$").search(path) != null: return MAX_REPLAY_TRANSFER_RESPONSE_BYTES
	if method == HTTPClient.METHOD_GET and RegEx.create_from_string("^/v2/rooms/[A-Za-z0-9_-]{22}/history/[0-9]{1,2}$").search(path) != null: return MAX_HISTORY_RESPONSE_BYTES
	return MAX_RESPONSE_BYTES

static func retry_after_ms(headers: PackedStringArray) -> int:
	for header: String in headers:
		if header.get_slice(":",0).strip_edges().to_lower()=="retry-after":
			var value := header.substr(header.find(":")+1).strip_edges()
			if value.is_valid_int(): return clampi(int(value),0,86400)*1000
	return 0

## The player's line for a refused or failed request. A server code with its
## own line keeps it; any other failure gets the general line for its route.
static func error_message(code: String, method: int = HTTPClient.METHOD_GET, path: String = "") -> String:
	var messages := {
		"stale_revision":PlayerCopy.ROOMS_API_D48EF12F6094,
		"wrong_turn":PlayerCopy.ROOMS_API_C28981B82853,
		"wrong_level":PlayerCopy.ROOMS_API_5835C935B81A,
		"source_recording_mismatch":PlayerCopy.ROOMS_API_EAFCF709F52F,
		"room_full":PlayerCopy.ROOMS_API_5CC5F70801E3,
		"room_limit_reached":PlayerCopy.ROOM_LIMIT_REACHED,
		"invite_expired":PlayerCopy.ROOMS_API_62C9BE05BAC1,
		"invite_not_found":PlayerCopy.ROOMS_API_D49E99BBEA43,
		"invalid_invite":PlayerCopy.ROOMS_API_57B8AA801916,
		"room_not_found":PlayerCopy.ROOMS_API_A7ACF38988EE,
		"room_deleted":PlayerCopy.ROOMS_API_1E67482A5FA2,
		"rate_limited":PlayerCopy.ROOMS_API_5743C6A33E2A,
		"host_unlock_required":PlayerCopy.ROOMS_API_93CCDC2D04DB,
		"entitlement_unavailable":PlayerCopy.ROOMS_API_5E389F16D75A,
		"partner_required":PlayerCopy.ROOMS_API_0D1594F23669,
		"invalid_auth":PlayerCopy.ROOMS_API_EB1D2050F3FD,
		"invalid_recovery":PlayerCopy.ROOMS_API_E8B889FD37A2,
		"idempotency_key_reused":PlayerCopy.ROOMS_API_6B7E9BF8BFEB,
		"unsupported_simulation_version":PlayerCopy.ROOMS_API_1AFC0FA5D7E2,
		"v2_mutations_disabled":PlayerCopy.ROOMS_API_B22D5D3F4AA1,
		"unsupported_catalog":PlayerCopy.ROOMS_API_C4C651453BA5,
		"unsupported_recording_version":PlayerCopy.ROOMS_API_1E1E03A869B2,
		"operation_not_found":PlayerCopy.ROOMS_API_238B348B3278,
		"room_history_full":PlayerCopy.ROOMS_API_C3BA080A81FF,
		"identity_unavailable":PlayerCopy.ROOMS_API_C35F1BDB3CB6,
		"not_found":PlayerCopy.ROOMS_API_B0F756999849,
		"room_finished":"This room has just finished, so it was kept.",
		"client_update_required":PlayerCopy.UPDATE_REQUIRED_ERROR,
	}
	return str(messages[code]) if messages.has(code) else for_route(PlayerCopy.ROOMS_API_1C556A121773,method,path)

## Only a turn being sent has a rehearsal on this phone, so only its failures
## say the rehearsal is kept. Hub, lobby and other routes get the line alone.
static func for_route(line: String, method: int, path: String) -> String:
	return line + " " + PlayerCopy.ROOM_TURN_KEPT if method == HTTPClient.METHOD_POST and path.ends_with("/turns") else line

static func new_key() -> String:
	return Crypto.new().generate_random_bytes(18).hex_encode()
