extends RefCounted
## Explicit client for opt-in friend room availability events.
## Callers invoke publish() only after a Friends-visible room has committed;
## its failure is independent from room creation and never blocks hosting.
const Presence = preload("res://services/friend_presence.gd")
const PENDING_PATH := "user://friend-room-publication-pending.cfg"
var busy := false
var last_error := ""
var _api: Node
var _identity: Callable
var _transport: Callable
var _binding: Dictionary = {}
var _pending_publication_id := ""
var _pending_room: Dictionary = {}
var _generation := 0

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
	busy = false
	last_error = ""

## The id is saved before the request and retained after network errors, so a
## retry cannot create a second publication if the first response was lost.
## A successful response clears the pending operation for the next room.
func publish(room: Variant) -> Dictionary:
	if not valid_room(room) or not _bind() or busy or _api.busy:
		last_error = "Friend room unavailable"
		return {"ok":false,"code":"client_unavailable"}
	if _pending_publication_id.is_empty() or _pending_room != room:
		_pending_publication_id = new_publication_id()
		_pending_room = room.duplicate(true)
		_save_pending()
	var body := {"schema_version":1,"room":room.duplicate(true),"publication_id":_pending_publication_id}
	var response := await _request(HTTPClient.METHOD_POST,"/v1/social/publication",body)
	if not response.get("ok",false): return response
	var data: Variant = response.get("data")
	if not valid_publication_ack(data):
		last_error = "Friend room unavailable"
		return {"ok":false,"code":"invalid_response"}
	_pending_publication_id = ""
	_pending_room = {}
	_save_pending()
	return {"ok":true,"data":data.duplicate(true)}

func inbox() -> Dictionary:
	if not _bind() or busy or _api.busy:
		last_error = "Friend activity unavailable"
		return {"ok":false,"code":"client_unavailable"}
	var response := await _request(HTTPClient.METHOD_GET,"/v1/social/inbox",{})
	if not response.get("ok",false): return response
	if not valid_inbox(response.get("data")):
		last_error = "Friend activity unavailable"
		return {"ok":false,"code":"invalid_response"}
	return {"ok":true,"data":response.data.duplicate(true)}

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
	return response.get("ok",false) and valid_subscription_ack(data,str(friend.request_id),enabled)

func _bind() -> bool:
	var current := context()
	if current.is_empty():
		_binding = {}
		_pending_publication_id = ""
		_pending_room = {}
		return false
	if current != _binding:
		_generation += 1
		_binding = current
		busy = false
		last_error = ""
		_load_pending()
	return true

func _request(method: int, path: String, body: Dictionary) -> Dictionary:
	if not _bind() or busy or _api.busy: return {"ok":false,"code":"client_unavailable"}
	busy = true
	last_error = ""
	var generation := _generation
	var binding := _binding.duplicate(true)
	var response: Variant = await _transport.call(method,path,body.duplicate(true)) if _transport.is_valid() else await _api.request_json(method,path,body)
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
	config.save(PENDING_PATH)

func _load_pending() -> void:
	_pending_publication_id = ""
	_pending_room = {}
	var config := ConfigFile.new()
	if config.load(PENDING_PATH) != OK: return
	var key := _cache_section()
	var publication_id: Variant = config.get_value(key,"publication_id","")
	var room: Variant = config.get_value(key,"room",{})
	if valid_publication_id(publication_id) and valid_room(room):
		_pending_publication_id = publication_id
		_pending_room = room.duplicate(true)

static func new_publication_id() -> String:
	return Marshalls.raw_to_base64(Crypto.new().generate_random_bytes(16)).replace("+","-").replace("/","_").trim_suffix("=").trim_suffix("=")

static func valid_publication_id(value: Variant) -> bool:
	if not value is String or value.length() != 22: return false
	for character: String in value:
		if character not in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-": return false
	return true

static func valid_room(value: Variant) -> bool:
	if not value is Dictionary or value.size() != 2 or not Presence.valid_id(value.get("room_id")): return false
	var version: Variant = value.get("api_version")
	return (version is int or version is float) and version in [1,2] and is_finite(float(version)) and float(version) == floor(float(version))

static func valid_friend(value: Variant) -> bool:
	return value is Dictionary and value.size() >= 2 and Presence.valid_id(value.get("player_id")) and Presence.valid_id(value.get("request_id"))

static func valid_publication_ack(value: Variant) -> bool:
	if not value is Dictionary or value.size() != 3 or value.get("schema_version") != 1: return false
	return _positive_integer(value.get("publication_epoch")) and _integer_between(value.get("queued"),0,20)

static func valid_inbox(value: Variant) -> bool:
	if not value is Dictionary or value.size() != 4 or value.get("schema_version") != 1 or not value.get("available") is bool: return false
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
	if not value is Dictionary or value.size() != 7 or value.get("category") != "room_available": return false
	if not Presence.valid_id(value.get("player_id")) or not Presence.valid_id(value.get("request_id")) or not valid_room(value.get("room")): return false
	if not _positive_integer(value.get("publication_epoch")) or not _positive_integer(value.get("published_at")): return false
	var event_id: Variant = value.get("event_id")
	return event_id is String and event_id == str(value.player_id)+"_"+str(value.publication_epoch) and event_id.length() <= 39

static func valid_ack_response(value: Variant, request_id: String) -> bool:
	return value is Dictionary and value.size() == 3 and value.get("schema_version") == 1 and value.get("acknowledged") == true and value.get("request_id") == request_id

static func valid_subscription_ack(value: Variant, request_id: String, enabled: bool) -> bool:
	return value is Dictionary and value.size() == 3 and value.get("schema_version") == 1 and value.get("subscribed") == enabled and value.get("request_id") == request_id

static func _positive_integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) > 0 and float(value) == floor(float(value))

static func _integer_between(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= minimum and float(value) <= maximum and float(value) == floor(float(value))
