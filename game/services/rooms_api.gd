extends Node
const PlayerCopy = preload("res://presentation/player_copy.gd")
## One bounded request at a time. Callers retain draft/idempotency state.
var base_url := ""
var player_id := ""
var device_token := ""
var busy := false

func configured() -> bool:
	return base_url.begins_with("https://") or (OS.has_feature("debug") and base_url.begins_with("http://127.0.0.1:"))

func request_json(method: int, path: String, body: Dictionary={}) -> Dictionary:
	if not configured():
		return {"ok":false,"status":0,"error":PlayerCopy.ROOMS_API_12A6D5364AAB}
	if busy:
		return {"ok":false,"status":0,"error":PlayerCopy.ROOMS_API_DA75E6F7A674}
	busy=true
	var request := HTTPRequest.new()
	request.timeout=20.0
	request.body_size_limit=4194304
	add_child(request)
	var headers := PackedStringArray(["Content-Type: application/json"])
	if not device_token.is_empty():
		headers.append("Authorization: Bearer "+device_token)
		headers.append("X-Player-Id: "+player_id)
	var result := request.request(base_url.trim_suffix("/")+path,headers,method,"" if method==HTTPClient.METHOD_GET else JSON.stringify(body))
	if result!=OK:
		request.queue_free()
		busy=false
		return {"ok":false,"status":0,"error":PlayerCopy.ROOMS_API_7795AD99E31E}
	var response: Array=await request.request_completed
	request.queue_free()
	busy=false
	var parser := JSON.new()
	var parsed: Variant=parser.data if parser.parse(response[3].get_string_from_utf8())==OK else null
	var payload: Dictionary=parsed if parsed is Dictionary else {}
	var status := int(response[1])
	var server_error: Variant=payload.get("error",{})
	var code := str(server_error.get("code","connection_interrupted")) if server_error is Dictionary else "connection_interrupted"
	return {"ok":response[0]==HTTPRequest.RESULT_SUCCESS and status>=200 and status<300 and parsed is Dictionary,"status":status,"data":payload,"error":error_message(code),"code":code,"retry_after_ms":retry_after_ms(response[2]),"retryable":bool(server_error.get("retryable",true)) if server_error is Dictionary else true}

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
	}
	return str(messages.get(code,PlayerCopy.ROOMS_API_1C556A121773))

static func new_key() -> String:
	return Crypto.new().generate_random_bytes(18).hex_encode()
