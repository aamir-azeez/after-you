extends Node
const PlayerCopy = preload("res://presentation/player_copy.gd")
## One bounded request at a time. Callers retain draft/idempotency state.
const MAX_RESPONSE_BYTES := 4194304
## The completed replay-transfer download carries its whole archive inline: at
## most the server's MAX_REPLAY_ARCHIVE_BYTES (16 MiB) plus a manifest of about
## 42 KB at its widest. Every other response keeps the 4 MiB cap.
const MAX_REPLAY_TRANSFER_RESPONSE_BYTES := 16 * 1024 * 1024 + 65536
var base_url := ""
var player_id := ""
var device_token := ""
var busy := false

func configured() -> bool:
	return base_url.begins_with("https://") or (OS.has_feature("debug") and base_url.begins_with("http://127.0.0.1:"))

func request_json(method: int, path: String, body: Dictionary={}) -> Dictionary:
	return await _request_json(method,path,body,false)

## One request with extra headers after the capability ones (the iOS registration's platform headers).
func request_json_with_headers(method: int, path: String, body: Dictionary, extra: PackedStringArray) -> Dictionary:
	return await _request_json(method,path,body,false,extra)

func request_campaign_json(method: int, path: String, body: Dictionary={}) -> Dictionary:
	# This negotiates wire support only. The owning campaign transport must
	# validate identity, publication and allowed operation before dispatch.
	return await _request_json(method,path,body,true)

func _request_json(method: int, path: String, body: Dictionary, campaign: bool, extra: PackedStringArray = PackedStringArray()) -> Dictionary:
	if not configured():
		return {"ok":false,"status":0,"error":PlayerCopy.ROOMS_API_12A6D5364AAB}
	if busy:
		return {"ok":false,"status":0,"error":PlayerCopy.ROOMS_API_DA75E6F7A674}
	busy=true
	var headers := capability_headers(method,path,campaign)
	headers.append_array(extra)
	if not device_token.is_empty():
		headers.append("Authorization: Bearer "+device_token)
		headers.append("X-Player-Id: "+player_id)
	var response: Array = await _send(method,path,headers,"" if method==HTTPClient.METHOD_GET else JSON.stringify(body))
	busy=false
	if response.is_empty():
		return {"ok":false,"status":0,"error":PlayerCopy.ROOMS_API_7795AD99E31E}
	var parser := JSON.new()
	var parsed: Variant=parser.data if parser.parse(response[3].get_string_from_utf8())==OK else null
	var payload: Dictionary=parsed if parsed is Dictionary else {}
	var status := int(response[1])
	var server_error: Variant=payload.get("error",{})
	var code := str(server_error.get("code","connection_interrupted")) if server_error is Dictionary else "connection_interrupted"
	return {"ok":response[0]==HTTPRequest.RESULT_SUCCESS and status>=200 and status<300 and parsed is Dictionary,"status":status,"data":payload,"error":error_message(code),"code":code,"retry_after_ms":retry_after_ms(response[2]),"retryable":bool(server_error.get("retryable",true)) if server_error is Dictionary else true}

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

## Server replies come from Godot's JSON parser, where every number is a float
## (2.0): `2.0 in [1,2]` is false, `2.0 is int` is false and str(4.0) is "4.0".
## The whole number a parsed JSON value holds, or `fallback` when it holds none.
static func json_int(value: Variant, fallback: int = -1) -> int:
	if not (value is int or value is float): return fallback
	var number := float(value)
	if not is_finite(number) or number != floor(number) or absf(number) > 9007199254740991.0: return fallback
	return int(number)

## The capability headers this build sends for one request (no credentials).
static func capability_headers(method: int, path: String, campaign: bool = false) -> PackedStringArray:
	var headers := PackedStringArray(["Content-Type: application/json"])
	if campaign: headers.append("X-AfterYou-Campaign-Schema: 2")
	# Room level 2: this build plays chapters with more than two stages, so the
	# server may list them and accept a longer join list. Older servers ignore it.
	if path == "/v2/capabilities": headers.append("X-AfterYou-Room-Level: 2")
	# The inbox then reports a room another member closed as "closed".
	if path == "/v1/room-inbox": headers.append("X-AfterYou-Room-Inbox: 2")
	# The friends list may then include the player's short name (friend_alias).
	if method == HTTPClient.METHOD_GET and path == "/v1/friends": headers.append("X-AfterYou-Friends: 2")
	# A finished room whose replay moved to the phones reads as finished here.
	if method == HTTPClient.METHOD_GET and path.begins_with("/v2/rooms/") and path.count("/") == 3: headers.append("X-AfterYou-Finished-Room: 2")
	# Closing a room only ever ends one still in play, never one that just finished.
	if method == HTTPClient.METHOD_DELETE and path.begins_with("/v") and path.count("/") == 3 and path.contains("/rooms/"): headers.append("X-AfterYou-Close-If: in-play")
	# This build reads hosting events, so the server may list them and push them
	# to this phone. Builds up to 0.6.0 rejected them and never get them.
	if path in ["/v1/social/inbox","/v1/notifications/registration"]: headers.append("X-AfterYou-Friend-Events: 2")
	return headers

static func response_limit(method: int, path: String) -> int:
	if method == HTTPClient.METHOD_GET and RegEx.create_from_string("^/v2/rooms/[A-Za-z0-9_-]{22}/replay-transfer$").search(path) != null: return MAX_REPLAY_TRANSFER_RESPONSE_BYTES
	return MAX_RESPONSE_BYTES

static func retry_after_ms(headers: PackedStringArray) -> int:
	for header: String in headers:
		if header.get_slice(":",0).strip_edges().to_lower()=="retry-after":
			var value := header.substr(header.find(":")+1).strip_edges()
			if value.is_valid_int(): return clampi(int(value),0,86400)*1000
	return 0

static func error_message(code: String) -> String:
	var messages := {
		"stale_revision":PlayerCopy.ROOMS_API_D48EF12F6094,
		"wrong_turn":PlayerCopy.ROOMS_API_C28981B82853,
		"wrong_level":PlayerCopy.ROOMS_API_5835C935B81A,
		"source_recording_mismatch":PlayerCopy.ROOMS_API_EAFCF709F52F,
		"room_full":PlayerCopy.ROOMS_API_5CC5F70801E3,
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
	}
	return str(messages.get(code,PlayerCopy.ROOMS_API_1C556A121773))

static func new_key() -> String:
	return Crypto.new().generate_random_bytes(18).hex_encode()
