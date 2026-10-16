extends RefCounted
## Explicit friends operations; polling is owned by the visible friends screen.
const Presence = preload("res://services/friend_presence.gd")
const Api = preload("res://services/rooms_api.gd")
const ShareCodes = preload("res://services/share_codes.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const Save = preload("res://services/local_save.gd")
const REFRESH_MS := 60000
const MIN_REFRESH_MS := 30000
const JOIN_COOLDOWN_MS := 3000
## A live hint's early read comes no sooner than this after the last read; the
## server grants the same early read when it sends the hint.
const LIVE_FLOOR_MS := 3000
var busy := false
var last_error := ""
## The server's error code for the last failed request, e.g. "room_not_found".
var last_code := ""
var clock_ms: Callable = Time.get_ticks_msec
var _api: Node
var _identity: Callable
var _transport: Callable
var _binding: Dictionary = {}
var _generation := 0
var _page: Dictionary = {}
var _observed_at := 0
var _next_refresh := 0
var _next_manual_refresh := 0
var _refresh_floor_ms := MIN_REFRESH_MS
var _retry_until := 0
var _next_join := 0
## When the last list reply arrived (always after the server served it, so a
## floor timed from here never comes before the server's own).
var _last_read_at := -LIVE_FLOOR_MS
## A friends hint came while a list read was out; that read may predate the change.
var _hinted_mid_read := false
## The room the server last confirmed as shared with friends (or null), from a
## share reply or a list page, so a room card can show it without a list read.
var _shared: Variant = null

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
	_next_manual_refresh = 0
	_refresh_floor_ms = MIN_REFRESH_MS
	_retry_until = 0
	_next_join = 0
	_last_read_at = -LIVE_FLOOR_MS
	_hinted_mid_read = false
	_shared = null
	busy = false
	last_error = ""

func view() -> Dictionary:
	if context().is_empty() or context() != _binding: return {}
	var result := _page.duplicate(true)
	for row: Dictionary in result.get("friends",[]):
		if int(clock_ms.call()) >= _observed_at + int(row.expires_after_seconds) * 1000:
			row.online = false
			row.expires_after_seconds = 0
	return result

## The room this player shares with friends, or null.
func shared_room() -> Variant:
	if context().is_empty() or context() != _binding: return null
	return _shared.duplicate(true) if _shared is Dictionary else null

## The player's short name from the current page (e.g. "aamir"), or "".
func friend_alias() -> String:
	var alias: Variant = view().get("friend_alias","")
	return alias if ShareCodes.is_alias(alias) else ""

## What this player shares: the short name when they have one, else their player ID.
func share_id() -> String:
	var alias := friend_alias()
	return alias if not alias.is_empty() else str(context().get("player_id",""))

func refresh_wait_ms(manual: bool = false) -> int:
	return maxi(0,maxi(_next_manual_refresh if manual else _next_refresh,_retry_until)-int(clock_ms.call()))

func refresh_due(manual: bool = false) -> bool:
	return refresh_wait_ms(manual) == 0

func join_wait_ms() -> int:
	return maxi(0,maxi(_next_join,_retry_until)-int(clock_ms.call()))

func refresh(manual: bool = false) -> bool:
	if not _bind() or busy: return false
	if not refresh_due(manual): return not _page.is_empty()
	var started := int(clock_ms.call())
	_hinted_mid_read = false
	_next_refresh = started + maxi(REFRESH_MS,_refresh_floor_ms)
	_next_manual_refresh = started + _refresh_floor_ms
	var response := await _request(HTTPClient.METHOD_GET,"/v1/friends")
	if not response.get("ok",false):
		# An early read the server had not opened (the change landed before it
		# served the previous one, or another phone of this player read the list)
		# waits for the server's own floor, not a minute, and never less than a few seconds.
		if str(response.get("code","")) == "friends_refresh_limited": _next_refresh = maxi(int(clock_ms.call()) + 2 * LIVE_FLOOR_MS, _last_read_at + _refresh_floor_ms)
		return false
	var data: Variant = response.get("data")
	if not valid_page(data,_binding.get("player_id","")):
		last_error = "Friends unavailable"
		return false
	_page = data.duplicate(true)
	_shared = _page.shared_room
	_observed_at = started
	_refresh_floor_ms = int(data.refresh_after_seconds) * 1000
	_next_manual_refresh = started + _refresh_floor_ms
	_next_refresh = started + maxi(REFRESH_MS,_refresh_floor_ms)
	_last_read_at = int(clock_ms.call())
	if _hinted_mid_read:
		_hinted_mid_read = false
		_next_refresh = mini(_next_refresh, _last_read_at + LIVE_FLOOR_MS)
	return true

## The live socket says the list changed. `granted` (a friends hint) makes the
## next read due now, at least LIVE_FLOOR_MS after the last; otherwise (the
## socket reopened) it comes as early as a manual refresh may.
func hint(granted: bool) -> void:
	if context().is_empty() or context() != _binding: return
	if granted and busy: _hinted_mid_read = true
	var due := maxi(int(clock_ms.call()), (_last_read_at + LIVE_FLOOR_MS) if granted else _next_manual_refresh)
	_next_refresh = mini(_next_refresh, due)

func add_friend(code: String) -> bool:
	# Accepts friend-<id>, a legacy bare ID or an invite link; the API receives only the bare ID.
	# A short name (friend-aamir) is sent as is and the server resolves it.
	var parsed := ShareCodes.parse(code,ShareCodes.FRIEND)
	if not parsed.ok or not (Presence.valid_id(parsed.id) or ShareCodes.is_alias(parsed.id)):
		last_error = ShareCodes.error_message(parsed,PlayerCopy.FRIEND_CODE_INVALID)
		return false
	if parsed.id in [context().get("player_id"),friend_alias()]: last_error = PlayerCopy.FRIEND_CODE_OWN; return false
	return await _mutation(HTTPClient.METHOD_POST,"/v1/friends/request",{"schema_version":1,"friend_code":parsed.id})

func accept_friend(row: Dictionary) -> bool:
	if not _row(row): return false
	return await _mutation(HTTPClient.METHOD_POST,"/v1/friends/accept",{"schema_version":1,"player_id":row.player_id,"request_id":row.request_id})

func remove_friend(row: Dictionary) -> bool:
	if not _row(row): return false
	return await _mutation(HTTPClient.METHOD_DELETE,"/v1/friends/"+str(row.player_id),{"schema_version":1,"request_id":row.request_id})

func share_room(room: Variant) -> bool:
	if room != null and not _room(room): return false
	var response := await _request(HTTPClient.METHOD_POST,"/v1/friends/share",{"schema_version":1,"room":room})
	if not response.get("ok",false): return false
	var data: Variant = response.get("data")
	if not data is Dictionary or data.size() != 2 or not Save.equal(data.get("schema_version"), 1) or not data.has("shared_room") or not same_room(data.shared_room,room):
		last_error = "Friends unavailable"
		return false
	# The response confirms only our sharing choice. Keep friends and their
	# original presence observation time without forcing another list request.
	_shared = room.duplicate(true) if room is Dictionary else null
	if not _page.is_empty(): _page.shared_room = room.duplicate(true) if room is Dictionary else null
	return true

func join_friend(row: Dictionary) -> Dictionary:
	if not _row(row) or not _bind() or busy or join_wait_ms() > 0: return {}
	_next_join = int(clock_ms.call()) + JOIN_COOLDOWN_MS
	var response := await _request(HTTPClient.METHOD_POST,"/v1/friends/"+str(row.player_id)+"/join",{"schema_version":1,"request_id":row.request_id})
	if not response.get("ok",false):
		if response.get("code","") in ["friend_not_joinable","friend_room_unavailable","room_full","friend_unavailable","friend_not_found","player_blocked","friend_request_changed"]:
			for peer: Dictionary in _page.get("friends",[]):
				if peer.player_id == row.player_id and peer.request_id == row.request_id: peer.join_available = false
		return {}
	var data: Variant = response.get("data")
	if not data is Dictionary or data.size() != 4 or not Save.equal(data.get("schema_version"), 1) or not _room({"api_version":data.get("api_version"),"room_id":data.get("room_id")}):
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
	var data: Variant = response.get("data")
	if method == HTTPClient.METHOD_DELETE:
		if not data is Dictionary or data.size() != 2 or not Save.equal(data.get("schema_version"), 1) or not Save.equal(data.get("removed"), true):
			last_error = "Friends unavailable"; return false
		if not _page.is_empty():
			_page.friends = _page.friends.filter(func(peer: Dictionary) -> bool: return peer.player_id != path.get_file() or peer.request_id != body.request_id)
	else:
		# A short name comes back as the player ID the server resolved it to.
		if not data is Dictionary or data.size() != 4 or not Save.equal(data.get("schema_version"), 1) or not _row(data) or data.get("status") not in ["incoming","outgoing","accepted"] or data.player_id == _binding.get("player_id") or (data.player_id != body.get("player_id",body.get("friend_code")) and not ShareCodes.is_alias(body.get("friend_code"))):
			last_error = "Friends unavailable"; return false
		if path.ends_with("/accept") and (data.request_id != body.request_id or data.status != "accepted"):
			last_error = "Friends unavailable"; return false
		if not _page.is_empty():
			# A link acknowledgement proves consent, not presence or sharing.
			# Its accepted row can immediately resolve a room via Check room.
			var row := {"player_id":data.player_id,"request_id":data.request_id,"status":data.status,"online":false,"expires_after_seconds":0,"join_available":false}
			var index: int = -1
			for i in range(_page.friends.size()):
				if _page.friends[i].player_id == data.player_id: index = i; break
			if index >= 0: _page.friends[index] = row
			elif _page.friends.size() < 20: _page.friends.append(row)
			else: _page = {}
	return true

func _bind() -> bool:
	var current := context()
	if current.is_empty(): last_error = "Friends unavailable"; return false
	if current != _binding:
		invalidate()
		_binding = current
	return true

func _request(method: int, path: String, body: Dictionary = {}) -> Dictionary:
	if not _bind() or busy: return {}
	busy = true
	last_error = ""
	last_code = ""
	var generation := _generation
	var response: Variant = await _transport.call(method,path,body.duplicate(true)) if _transport.is_valid() else await _api.request_json(method,path,body,func() -> bool: return generation == _generation and context() == _binding)
	if generation != _generation: return {}
	if context() != _binding:
		invalidate()
		return {}
	busy = false
	if not response is Dictionary: last_error = "Friends unavailable"; return {}
	if not response.get("ok",false):
		var code := str(response.get("code",""))
		last_code = code
		var retry := maxi(0,int(response.get("retry_after_ms",0)))
		if code == "rate_limited": retry = maxi(REFRESH_MS,retry)
		# The list's own floor: refresh() waits for exactly that, not the generic minute.
		var list_floor := code == "friends_refresh_limited" and method == HTTPClient.METHOD_GET and path == "/v1/friends"
		if retry > 0 and not list_floor: _retry_until = maxi(_retry_until,int(clock_ms.call()) + retry)
		if method == HTTPClient.METHOD_GET and path == "/v1/friends" and not list_floor:
			_next_refresh = maxi(_next_refresh,int(clock_ms.call()) + REFRESH_MS)
		last_error = "Friend unavailable" if code in ["friend_unavailable","friend_not_found","player_blocked"] else "Room unavailable" if code in ["friend_room_unavailable","friend_not_joinable","room_full"] else "Friends unavailable"
	return response

static func _row(value: Dictionary) -> bool:
	return Presence.valid_id(value.get("player_id")) and Presence.valid_id(value.get("request_id"))

static func _room(value: Variant) -> bool:
	if not value is Dictionary or value.size() != 2 or not Presence.valid_id(value.get("room_id")): return false
	var version: Variant = value.get("api_version")
	return (version is int or version is float) and (version == 1 or version == 2)

static func same_room(left: Variant, right: Variant) -> bool:
	if left == null or right == null: return left == null and right == null
	# JSON decodes integral numbers as floats. Compare the validated fields,
	# not Dictionary equality, which also compares the numeric variant types.
	return _room(left) and _room(right) and left.api_version == right.api_version and left.room_id == right.room_id

static func valid_page(value: Variant, owner: String) -> bool:
	# friend_alias is the only optional key: the player's short name, sent when the request asks for it.
	if value is Dictionary and value.has("friend_alias") and not ShareCodes.is_alias(value.friend_alias): return false
	if not value is Dictionary or value.size() != (6 if value.has("friend_alias") else 5) or not value.has("shared_room") or not Save.equal(value.get("schema_version"), 1) or not Save.equal(value.get("friend_code"), owner) or not value.get("friends") is Array or value.friends.size() > 20: return false
	var refresh: Variant = value.get("refresh_after_seconds")
	if not (refresh is int or refresh is float) or not is_finite(refresh) or refresh < 30 or refresh > 3600 or refresh != floor(refresh): return false
	if value.get("shared_room") != null and not _room(value.shared_room): return false
	var peers := {}
	for row: Variant in value.friends:
		if not row is Dictionary or row.size() != 6 or not _row(row) or row.player_id == owner or peers.has(row.player_id) or row.get("status") not in ["incoming","outgoing","accepted"] or not row.get("online") is bool or not row.get("join_available") is bool: return false
		var ttl: Variant = row.get("expires_after_seconds")
		if not (ttl is int or ttl is float) or not is_finite(ttl) or ttl < 0 or ttl > 90 or ttl != floor(ttl): return false
		if row.online != (ttl > 0) or ((row.online or row.join_available) and row.status != "accepted"): return false
		peers[row.player_id] = true
	return true
