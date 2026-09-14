extends Node
## One bounded request at a time. Callers retain draft/idempotency state.
var base_url := ""
var player_id := ""
var device_token := ""
var busy := false

func configured() -> bool:
	return base_url.begins_with("https://") or (OS.has_feature("debug") and base_url.begins_with("http://127.0.0.1:"))

func request_json(method: int, path: String, body: Dictionary={}) -> Dictionary:
	if not configured():
		return {"ok":false,"status":0,"error":"Online rooms are not configured in this build. Solo practice is available."}
	if busy:
		return {"ok":false,"status":0,"error":"A room request is already in progress."}
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
		return {"ok":false,"status":0,"error":"Unable to connect. Your draft is still on this device."}
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
		"stale_revision":"Your friend changed this room. Refresh before reviewing your turn again.",
		"wrong_turn":"It is your friend's turn. Your rehearsal has been kept.",
		"wrong_level":"This room has moved to another island. Your rehearsal has been kept.",
		"source_recording_mismatch":"The earlier recording changed. Start a new rehearsal alongside the current ghost.",
		"room_full":"This room already has two players.",
		"invite_expired":"This invitation expired. Ask your friend for a new room code.",
		"invite_not_found":"That invitation code was not found.",
		"invalid_invite":"Check the invitation code and try again.",
		"room_not_found":"This room is unavailable or has been deleted.",
		"room_deleted":"This room has been deleted.",
		"rate_limited":"The service is busy. Wait a little before trying again.",
		"host_unlock_required":"The room host needs Full Journey to continue to this island.",
		"entitlement_unavailable":"The store could not verify the host's unlock. Try again later.",
		"partner_required":"Invite your friend before moving to the next island.",
		"invalid_auth":"Your device identity is no longer valid. Use your recovery code in Account & recovery.",
		"invalid_recovery":"That identity and recovery code did not match.",
		"idempotency_key_reused":"This saved request no longer matches its original turn. It has been held for review.",
		"unsupported_simulation_version":"This recording needs a compatible app version.",
		"v2_mutations_disabled":"Online Relay creation and submissions are paused. Your existing rooms and drafts are kept.",
		"unsupported_catalog":"This Relay chapter requires a compatible app version.",
		"unsupported_recording_version":"This contribution requires a compatible Relay app version.",
		"operation_not_found":"That saved request has no receipt yet. The exact request can be retried.",
		"room_history_full":"This room's retained history is full. Its existing memories remain available.",
		"identity_unavailable":"Recover or reload your identity before checking this room.",
		"not_found":"This feature is not available from the current service. Your saved progress is kept.",
	}
	return str(messages.get(code,"Connection interrupted or request unavailable. Your rehearsal is still on this device."))

static func new_key() -> String:
	return Crypto.new().generate_random_bytes(18).hex_encode()
