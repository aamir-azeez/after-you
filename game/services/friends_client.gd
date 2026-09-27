extends RefCounted
## Explicit friends operations; polling is owned by the visible friends screen.
const Presence = preload("res://services/friend_presence.gd")
const Api = preload("res://services/rooms_api.gd")
const REFRESH_MS := 60000
var busy := false
var last_error := ""
var clock_ms: Callable = Time.get_ticks_msec
var _api: Node
var _identity: Callable
var _transport: Callable
var _binding: Dictionary = {}
var _generation := 0
var _page: Dictionary = {}
var _observed_at := 0
var _next_refresh := 0

func _init(api: Node, identity: Callable, transport: Callable = Callable()) -> void:
	_api = api
	_identity = identity
	_transport = transport

func context() -> Dictionary:
	var value: Variant = _identity.call() if _identity.is_valid() else null
	if not value is Dictionary or value.get("ready") != true or not Presence.valid_id(value.get("player_id")): return {}
	if not is_instance_valid(_api) or _api.player_id != value.player_id or _api.device_token.is_empty(): return {}
	return {"player_id":value.player_id,"epoch":value.get("epoch",0),"base_url":_api.base_url,"credential_hash":str(_api.device_token).sha256_text()}

func invalidate() -> void:
	_generation += 1
	_binding = {}
	_page = {}
	_next_refresh = 0
	busy = false
	last_error = ""

func view() -> Dictionary:
	if context().is_empty() or context() != _binding: return {}
	var result := _page.duplicate(true)
	for row: Dictionary in result.get("friends",[]):
		if int(clock_ms.call()) >= _observed_at + int(row.expires_after_seconds) * 1000:
			row.online = false
			row.join_available = false
			row.expires_after_seconds = 0
	return result

func refresh_due() -> bool:
	return int(clock_ms.call()) >= _next_refresh

func refresh() -> bool:
	if not _bind(): return false
	if not refresh_due(): return not _page.is_empty()
	var started := int(clock_ms.call())
	_next_refresh = started + REFRESH_MS
	var response := await _request(HTTPClient.METHOD_GET,"/v1/friends")
	if not response.get("ok",false): return false
	var data: Variant = response.get("data")
	if not valid_page(data,_binding.get("player_id","")):
		last_error = "Friends unavailable"
		return false
	_page = data.duplicate(true)
	_observed_at = started
	return true

func add_friend(code: String) -> bool:
	code = code.strip_edges()
	if not Presence.valid_id(code): last_error = "Invalid friend code"; return false
	return await _mutation(HTTPClient.METHOD_POST,"/v1/friends/request",{"schema_version":1,"friend_code":code})

func accept_friend(row: Dictionary) -> bool:
	if not _row(row): return false
	return await _mutation(HTTPClient.METHOD_POST,"/v1/friends/accept",{"schema_version":1,"player_id":row.player_id,"request_id":row.request_id})

func remove_friend(row: Dictionary) -> bool:
	if not _row(row): return false
	return await _mutation(HTTPClient.METHOD_DELETE,"/v1/friends/"+str(row.player_id),{"schema_version":1,"request_id":row.request_id})

func share_room(room: Variant) -> bool:
	if room != null and not _room(room): return false
	return await _mutation(HTTPClient.METHOD_POST,"/v1/friends/share",{"schema_version":1,"room":room})

func join_friend(row: Dictionary) -> Dictionary:
	if not _row(row): return {}
	var response := await _request(HTTPClient.METHOD_POST,"/v1/friends/"+str(row.player_id)+"/join",{"schema_version":1,"request_id":row.request_id})
	if not response.get("ok",false): return {}
	var data: Variant = response.get("data")
	if not data is Dictionary or data.size() != 4 or data.get("schema_version") != 1 or not _room({"api_version":data.get("api_version"),"room_id":data.get("room_id")}):
		last_error = "Room unavailable"; return {}
	var code: Variant = data.get("invite_code")
	if not code is String or code.length() != 20: last_error = "Room unavailable"; return {}
	for character: String in code:
		if character not in "0123456789ABCDEF": last_error = "Room unavailable"; return {}
	var expected: String = (("v2:" if data.api_version == 2 else "") + code).sha256_text().substr(0,22)
	if expected != data.room_id: last_error = "Room unavailable"; return {}
	return data.duplicate(true)

func _mutation(method: int, path: String, body: Dictionary) -> bool:
	var response := await _request(method,path,body)
	if not response.get("ok",false): return false
	_next_refresh = 0
	# Do not retain an online/join affordance after removing a friend or room.
	_page = {}
	return true

func _bind() -> bool:
	var current := context()
	if current.is_empty(): last_error = "Friends unavailable"; return false
	if current != _binding:
		invalidate()
		_binding = current
	return true

func _request(method: int, path: String, body: Dictionary = {}) -> Dictionary:
	if not _bind() or busy or _api.busy: return {}
	busy = true
	last_error = ""
	var generation := _generation
	var response: Variant = await _transport.call(method,path,body.duplicate(true)) if _transport.is_valid() else await _api.request_json(method,path,body)
	if generation != _generation: return {}
	if context() != _binding:
		invalidate()
		return {}
	busy = false
	if not response is Dictionary: last_error = "Friends unavailable"; return {}
	if not response.get("ok",false):
		_next_refresh = maxi(_next_refresh,int(clock_ms.call()) + maxi(REFRESH_MS,int(response.get("retry_after_ms",0))))
		var code := str(response.get("code",""))
		last_error = "Friend unavailable" if code in ["friend_unavailable","friend_not_found","player_blocked"] else "Room unavailable" if code in ["friend_room_unavailable","room_full"] else "Friends unavailable"
	return response

static func _row(value: Dictionary) -> bool:
	return Presence.valid_id(value.get("player_id")) and Presence.valid_id(value.get("request_id"))

static func _room(value: Variant) -> bool:
	if not value is Dictionary or value.size() != 2 or not Presence.valid_id(value.get("room_id")): return false
	var version: Variant = value.get("api_version")
	return (version is int or version is float) and (version == 1 or version == 2)

static func valid_page(value: Variant, owner: String) -> bool:
	if not value is Dictionary or value.size() != 5 or not value.has("shared_room") or value.get("schema_version") != 1 or value.get("friend_code") != owner or not value.get("friends") is Array or value.friends.size() > 20: return false
	var refresh: Variant = value.get("refresh_after_seconds")
	if not (refresh is int or refresh is float) or not is_finite(refresh) or refresh < 30 or refresh > 3600 or refresh != floor(refresh): return false
	if value.get("shared_room") != null and not _room(value.shared_room): return false
	var peers := {}
	for row: Variant in value.friends:
		if not row is Dictionary or row.size() != 6 or not _row(row) or row.player_id == owner or peers.has(row.player_id) or row.get("status") not in ["incoming","outgoing","accepted"] or not row.get("online") is bool or not row.get("join_available") is bool: return false
		var ttl: Variant = row.get("expires_after_seconds")
		if not (ttl is int or ttl is float) or not is_finite(ttl) or ttl < 0 or ttl > 90 or ttl != floor(ttl): return false
		if row.online != (ttl > 0) or (row.online and row.status != "accepted") or (row.join_available and not row.online): return false
		peers[row.player_id] = true
	return true
