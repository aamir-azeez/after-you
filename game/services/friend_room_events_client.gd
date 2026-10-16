extends RefCounted
## Explicit client for opt-in friend room availability events.
## Callers invoke publish() only after a Friends-visible room has committed;
## its failure is independent from room creation and never blocks hosting.
const Presence = preload("res://services/friend_presence.gd")
const RoomsApi = preload("res://services/rooms_api.gd")
const Typed = preload("res://services/typed_values.gd")
const PENDING_PATH := "user://friend-room-publication-pending.cfg"
## An owed hosting alert older than the server's event lifetime is dropped.
const OWED_TTL_S := 24 * 60 * 60
var busy := false
var last_error := ""
var _api: Node
var _identity: Callable
var _transport: Callable
var _binding: Dictionary = {}
var _pending_publication_id := ""
var _pending_room: Dictionary = {}
## When the pending alert became owed (unix seconds); 0 for none or legacy.
var _pending_owed_at := 0
var _generation := 0
## Last known hosting alerts for this identity, peer id -> true. A reopened
## Friends page starts from this instead of waiting for the next inbox read.
var _preferences: Dictionary = {}

func _init(api: Node, identity: Callable, transport: Callable = Callable()) -> void:
	_api = api
	_identity = identity
	_transport = transport
	_bind()

func context() -> Dictionary:
	var value: Variant = _identity.call() if _identity.is_valid() else null
	if not value is Dictionary or value.get("ready") != true or not Presence.valid_id(value.get("player_id")): return {}
	if not is_instance_valid(_api) or _api.player_id != value.player_id or _api.device_token.is_empty(): return {}
	var server := str(_api.base_url).trim_suffix("/")
	if server.is_empty(): return {}
	return {"player_id":value.player_id,"epoch":value.get("epoch",0),"server":server,"credential_hash":str(_api.device_token).sha256_text()}

func invalidate() -> void:
	_generation += 1
	_binding = {}
	_pending_publication_id = ""
	_pending_room = {}
	_pending_owed_at = 0
	_preferences = {}
	busy = false
	last_error = ""

## A Friends room just hosted owes one hosting alert. It is saved at once, so a
## restart before the share or the alert lands keeps it; publish() then reuses
## the same id and the server counts it once. One room at a time is owed.
func owe(room: Variant) -> bool:
	if not valid_room(room) or not _bind(): return false
	_pending_publication_id = new_publication_id()
	_pending_room = _plain_room(room)
	_pending_owed_at = int(Time.get_unix_time_from_system())
	_save_pending()
	return true

## Whether this room still owes its alert. Older than a day, or saved by a
## build that did not record when, it is dropped instead.
func owes(room: Variant) -> bool:
	if not valid_room(room) or not _bind() or _pending_publication_id.is_empty() or not _same(_pending_room, room): return false
	if _pending_owed_at <= 0 or int(Time.get_unix_time_from_system()) - _pending_owed_at >= OWED_TTL_S:
		_clear_pending()
		return false
	return true

## The room closed, finished or can no longer be shared: drop its alert.
func forget(room: Variant) -> void:
	if valid_room(room) and _bind() and not _pending_publication_id.is_empty() and _same(_pending_room, room): _clear_pending()

func _clear_pending() -> void:
	_pending_publication_id = ""
	_pending_room = {}
	_pending_owed_at = 0
	_save_pending()

static func _same(left: Variant, right: Variant) -> bool:
	return valid_room(left) and valid_room(right) and RoomsApi.json_int(left.api_version) == RoomsApi.json_int(right.api_version) and left.room_id == right.room_id

static func _plain_room(room: Dictionary) -> Dictionary:
	return {"api_version":RoomsApi.json_int(room.api_version),"room_id":str(room.room_id)}

## Sends the one alert a room owes, under the id owe() saved before any
## request; a failure keeps that id, so a retry cannot alert twice. A room
## that owes nothing (its alert landed or was forgotten) sends nothing and
## reports ok, so a caller that waited behind a slow reply cannot alert again.
func publish(room: Variant) -> Dictionary:
	if not valid_room(room) or not _bind() or busy:
		last_error = "Friend room unavailable"
		return {"ok":false,"code":"client_unavailable"}
	if not owes(room): return {"ok":true,"code":"not_owed"}
	var sent_id := _pending_publication_id
	var body := {"schema_version":1,"room":room.duplicate(true),"publication_id":sent_id}
	# An alert waiting its turn in the request queue goes out only while its id is still the owed one.
	var response := await _request(HTTPClient.METHOD_POST,"/v1/social/publication",body,func() -> bool: return _pending_publication_id == sent_id)
	if not response.get("ok",false): return response
	var data: Variant = response.get("data")
	if not valid_publication_ack(data):
		last_error = "Friend room unavailable"
		return {"ok":false,"code":"invalid_response"}
	# Another room may have become owed while this reply was on its way.
	if _pending_publication_id == sent_id: _clear_pending()
	return {"ok":true,"data":data.duplicate(true)}

func inbox() -> Dictionary:
	if not _bind() or busy:
		last_error = "Friend activity unavailable"
		return {"ok":false,"code":"client_unavailable"}
	var response := await _request(HTTPClient.METHOD_GET,"/v1/social/inbox",{})
	if not response.get("ok",false): return response
	if not valid_inbox(response.get("data")):
		last_error = "Friend activity unavailable"
		return {"ok":false,"code":"invalid_response"}
	_preferences = {}
	for preference: Dictionary in response.data.preferences:
		if preference.enabled: _preferences[str(preference.player_id)] = true
	return {"ok":true,"data":response.data.duplicate(true)}

## Hosting alerts as last read or saved for the current identity.
func hosting_preferences() -> Dictionary:
	if not _bind(): return {}
	return _preferences.duplicate()

## Acknowledge only after the corresponding event was actually rendered.
func acknowledge_rendered(event: Variant) -> bool:
	if not valid_event(event) or not _bind(): return false
	var response: Dictionary = await _request(HTTPClient.METHOD_POST,"/v1/friends/"+str(event.player_id)+"/notifications",{
		"schema_version":1,"request_id":event.request_id,"action":"ack","event_id":event.event_id})
	return response.get("ok",false) and valid_ack_response(response.get("data"),str(event.request_id))

func set_hosting_alert(friend: Variant, enabled: bool) -> bool:
	if not valid_friend(friend) or not _bind(): return false
	var response: Dictionary = await _request(HTTPClient.METHOD_POST,"/v1/friends/"+str(friend.player_id)+"/notifications",{
		"schema_version":1,"request_id":friend.request_id,"action":"subscribe" if enabled else "unsubscribe"})
	var data: Variant = response.get("data")
	var saved: bool = response.get("ok",false) and valid_subscription_ack(data,str(friend.request_id),enabled)
	if saved:
		if enabled: _preferences[str(friend.player_id)] = true
		else: _preferences.erase(str(friend.player_id))
	return saved

func _bind() -> bool:
	var current := context()
	if current.is_empty():
		_binding = {}
		_pending_publication_id = ""
		_pending_room = {}
		_pending_owed_at = 0
		_preferences = {}
		return false
	if current != _binding:
		_generation += 1
		_binding = current
		_preferences = {}
		busy = false
		last_error = ""
		_load_pending()
	return true

## `still`, when given, is the caller's own check for when its turn in the request queue comes.
func _request(method: int, path: String, body: Dictionary, still: Callable = Callable()) -> Dictionary:
	if not _bind() or busy: return {"ok":false,"code":"client_unavailable"}
	busy = true
	last_error = ""
	var generation := _generation
	var binding := _binding.duplicate(true)
	var response: Variant = await _transport.call(method,path,body.duplicate(true)) if _transport.is_valid() else await _api.request_json(method,path,body,func() -> bool: return generation == _generation and context() == binding and (still.is_null() or (still.is_valid() and still.call())))
	if generation != _generation or context() != binding:
		busy = false
		_bind()
		return {"ok":false,"code":"context_changed"}
	busy = false
	if not response is Dictionary:
		last_error = "Friend activity unavailable"
		return {"ok":false,"code":"invalid_response"}
	if not response.get("ok",false):
		last_error = "Friend activity unavailable"
		return response
	if not response.get("data") is Dictionary:
		last_error = "Friend activity unavailable"
		return {"ok":false,"code":"invalid_response"}
	return response

func _cache_section() -> String:
	return "publication_"+(_binding.server+"|"+_binding.player_id).sha256_text()

func _save_pending() -> void:
	if _binding.is_empty(): return
	var config := ConfigFile.new()
	config.load(PENDING_PATH)
	var key := _cache_section()
	if _pending_publication_id.is_empty():
		config.erase_section(key)
	else:
		config.set_value(key,"publication_id",_pending_publication_id)
		config.set_value(key,"room",_pending_room)
		config.set_value(key,"owed_at",_pending_owed_at)
	config.save(PENDING_PATH)

func _load_pending() -> void:
	_pending_publication_id = ""
	_pending_room = {}
	_pending_owed_at = 0
	var config := ConfigFile.new()
	if config.load(PENDING_PATH) != OK: return
	var key := _cache_section()
	var publication_id: Variant = config.get_value(key,"publication_id","")
	var room: Variant = config.get_value(key,"room",{})
	if valid_publication_id(publication_id) and valid_room(room):
		_pending_publication_id = publication_id
		_pending_room = _plain_room(room)
		_pending_owed_at = RoomsApi.json_int(config.get_value(key,"owed_at",0),0)

static func new_publication_id() -> String:
	return Marshalls.raw_to_base64(Crypto.new().generate_random_bytes(16)).replace("+","-").replace("/","_").trim_suffix("=").trim_suffix("=")

static func valid_publication_id(value: Variant) -> bool:
	if not value is String or value.length() != 22: return false
	for character: String in value:
		if character not in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-": return false
	return true

static func valid_room(value: Variant) -> bool:
	if not value is Dictionary or value.size() != 2 or not Presence.valid_id(value.get("room_id")): return false
	return RoomsApi.json_int(value.get("api_version")) in [1,2]

static func valid_friend(value: Variant) -> bool:
	return value is Dictionary and value.size() >= 2 and Presence.valid_id(value.get("player_id")) and Presence.valid_id(value.get("request_id"))

static func valid_publication_ack(value: Variant) -> bool:
	if not value is Dictionary or value.size() != 3 or not Typed.equal(value.get("schema_version"), 1): return false
	return _positive_integer(value.get("publication_epoch")) and _integer_between(value.get("queued"),0,20)

static func valid_inbox(value: Variant) -> bool:
	if not value is Dictionary or value.size() != 4 or not Typed.equal(value.get("schema_version"), 1) or not value.get("available") is bool: return false
	if not value.get("events") is Array or value.events.size() > 20 or not value.get("preferences") is Array or value.preferences.size() > 20: return false
	var seen_events := {}
	for event: Variant in value.events:
		if not valid_event(event) or seen_events.has(event.event_id): return false
		seen_events[event.event_id] = true
	var seen_preferences := {}
	for preference: Variant in value.preferences:
		if not preference is Dictionary or preference.size() != 3 or not Presence.valid_id(preference.get("player_id")) or not Presence.valid_id(preference.get("request_id")) or not preference.get("enabled") is bool or seen_preferences.has(preference.player_id): return false
		seen_preferences[preference.player_id] = true
	return true

static func valid_event(value: Variant) -> bool:
	if not value is Dictionary or value.size() != 7 or not Typed.equal(value.get("category"), "room_available"): return false
	if not Presence.valid_id(value.get("player_id")) or not Presence.valid_id(value.get("request_id")) or not valid_room(value.get("room")): return false
	if not _positive_integer(value.get("publication_epoch")) or not _positive_integer(value.get("published_at")): return false
	var event_id: Variant = value.get("event_id")
	return event_id is String and event_id == str(value.player_id)+"_"+str(RoomsApi.json_int(value.publication_epoch)) and event_id.length() <= 39

static func valid_ack_response(value: Variant, request_id: String) -> bool:
	return value is Dictionary and value.size() == 3 and Typed.equal(value.get("schema_version"), 1) and Typed.equal(value.get("acknowledged"), true) and Typed.equal(value.get("request_id"), request_id)

static func valid_subscription_ack(value: Variant, request_id: String, enabled: bool) -> bool:
	return value is Dictionary and value.size() == 3 and Typed.equal(value.get("schema_version"), 1) and Typed.equal(value.get("subscribed"), enabled) and Typed.equal(value.get("request_id"), request_id)

static func _positive_integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) > 0 and float(value) == floor(float(value))

static func _integer_between(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= minimum and float(value) <= maximum and float(value) == floor(float(value))
