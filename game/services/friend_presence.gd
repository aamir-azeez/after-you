extends Node
## Ephemeral room-private presence, independent of gameplay transport and journals.
signal changed
const Api = preload("res://services/rooms_api.gd")
const INTERVAL_MS := 30000
const SINGLETON_NAME := "AfterYouFriendPresence"
var api: Node
var clock_ms: Callable = Time.get_ticks_msec
var enabled := true
var foreground := true
var _identity: Dictionary = {}
var _identity_key := ""
var _session_id := ""
var _generation := 0
var _room := ""
var _family := ""
var _room_generation := 0
var _next_heartbeat := 0
var _next_read := 0
var _busy := false
var _lease_may_exist := false
var _offline_job: Dictionary = {}
var _state := "checking"
var _fresh_until := 0

static func shared(tree: SceneTree) -> Node:
	var existing := tree.root.get_node_or_null(SINGLETON_NAME)
	if existing == null and tree.root.has_meta(SINGLETON_NAME): existing = tree.root.get_meta(SINGLETON_NAME)
	if existing != null: return existing
	var service: Node = load("res://services/friend_presence.gd").new()
	service.name = SINGLETON_NAME
	tree.root.set_meta(SINGLETON_NAME, service)
	tree.root.add_child.call_deferred(service)
	return service

func _ready() -> void:
	if api == null: api = Api.new()
	if api.get_parent() == null: add_child(api)

func set_identity(value: Dictionary) -> void:
	var key := identity_key(value)
	if key == _identity_key: return
	_queue_offline()
	_generation += 1
	_identity_key = key
	_identity = value.duplicate(true) if not key.is_empty() else {}
	_session_id = Api.new_key() if not key.is_empty() else ""
	_lease_may_exist = false
	_next_heartbeat = 0
	_next_read = 0
	_set_state("checking")

func set_enabled(value: bool) -> void:
	if enabled == value: return
	if not value: _queue_offline()
	enabled = value
	_generation += 1
	if value and not _identity_key.is_empty(): _session_id = Api.new_key()
	_next_heartbeat = 0

func set_foreground(value: bool) -> void:
	if foreground == value: return
	if not value: _queue_offline()
	foreground = value
	_generation += 1
	if value and not _identity_key.is_empty(): _session_id = Api.new_key()
	_next_heartbeat = 0
	_next_read = 0
	_set_state("checking")

func monitor_room(family: String, room_id: String) -> void:
	if family not in ["v1", "v2"] or not valid_id(room_id):
		family = ""
		room_id = ""
	if _family == family and _room == room_id: return
	_family = family
	_room = room_id
	_room_generation += 1
	_next_read = 0
	_set_state("checking")

func view(family: String, room_id: String) -> Dictionary:
	var state := _state if family == _family and room_id == _room else "checking"
	if _identity_key.is_empty() or not foreground: state = "checking"
	if state == "online" and int(clock_ms.call()) >= _fresh_until: state = "checking"
	var labels := {"checking": "Checking friend status…", "unknown": "Friend status unavailable", "waiting": "Waiting for friend", "online": "Friend online", "offline": "Friend offline"}
	return {"state": state, "text": labels[state]}

func _process(_delta: float) -> void:
	service()

func service() -> void:
	if not is_inside_tree() or api == null: return
	var now := int(clock_ms.call())
	if _state == "online" and now >= _fresh_until: _set_state("checking")
	if _busy or api.busy: return
	if not _offline_job.is_empty():
		var job := _offline_job
		_offline_job = {}
		await _request(job.identity, HTTPClient.METHOD_POST, "/v1/presence", {"schema_version": 1, "session_id": job.session_id, "online": false})
		return # Best effort once; an unavailable server expires the lease.
	if not foreground or _identity_key.is_empty(): return
	if enabled and now >= _next_heartbeat:
		_next_heartbeat = now + INTERVAL_MS
		_lease_may_exist = true # Even a lost acknowledgement can have arrived.
		var generation := _generation
		var result := await _request(_identity, HTTPClient.METHOD_POST, "/v1/presence", {"schema_version": 1, "session_id": _session_id, "online": true})
		if generation != _generation: return
		_next_heartbeat = maxi(_next_heartbeat, int(clock_ms.call()) + retry_delay(result))
		# A heartbeat acknowledgement never establishes the partner's status.
		return
	if not _room.is_empty() and now >= _next_read:
		_next_read = now + INTERVAL_MS
		var generation := _generation
		var room_generation := _room_generation
		var result := await _request(_identity, HTTPClient.METHOD_GET, "/" + _family + "/rooms/" + _room + "/presence")
		if generation != _generation or room_generation != _room_generation: return
		_next_read = maxi(_next_read, int(clock_ms.call()) + retry_delay(result))
		var data: Variant = result.get("data")
		if not result.get("ok", false) or not valid_room_response(data):
			_set_state("unknown")
			return
		# Server TTL was observed before transit, so never add the round trip to it.
		_fresh_until = now + int(data.expires_after_seconds) * 1000
		_set_state("waiting" if not data.partner_joined else "online" if data.partner_online else "offline", false)

func _request(identity: Dictionary, method: int, path: String, body: Dictionary = {}) -> Dictionary:
	_busy = true
	api.base_url = identity.base_url
	api.player_id = identity.player_id
	api.device_token = identity.device_token
	var result: Dictionary = await api.request_json(method, path, body)
	# Credentials are needed only while constructing request headers, not retained
	# in the transport between requests or after an identity invalidation.
	api.player_id = ""
	api.device_token = ""
	_busy = false
	return result

func _queue_offline() -> void:
	if _lease_may_exist and not _identity.is_empty():
		_offline_job = {"identity": _identity.duplicate(true), "session_id": _session_id}
		_lease_may_exist = false

func _set_state(value: String, clear_fresh: bool = true) -> void:
	_state = value
	if clear_fresh: _fresh_until = 0
	changed.emit()

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_CLOSE_REQUEST]:
		set_foreground(false)
		service()
	elif what in [NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_APPLICATION_FOCUS_IN]:
		set_foreground(true)

func _exit_tree() -> void:
	if get_tree().root.has_meta(SINGLETON_NAME) and get_tree().root.get_meta(SINGLETON_NAME) == self: get_tree().root.remove_meta(SINGLETON_NAME)
	_generation += 1
	_identity.clear()
	_identity_key = ""
	_offline_job.clear()
	_session_id = ""
	if is_instance_valid(api):
		api.player_id = ""
		api.device_token = ""

static func identity_key(value: Dictionary) -> String:
	if value.get("ready") != true or not valid_id(value.get("player_id")) or not value.get("device_token") is String or value.device_token.is_empty() or not value.get("base_url") is String or value.base_url.is_empty() or not value.get("epoch") is int: return ""
	return JSON.stringify([value.base_url, value.player_id, value.device_token.sha256_text(), value.epoch])

static func valid_id(value: Variant) -> bool:
	if not value is String or value.length() != 22: return false
	for character: String in value:
		if not character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-": return false
	return true

static func valid_room_response(value: Variant) -> bool:
	if not value is Dictionary or value.size() != 4 or not (value.get("schema_version") is int or value.get("schema_version") is float) or value.schema_version != 1 or not value.get("partner_joined") is bool or not value.get("partner_online") is bool: return false
	var ttl: Variant = value.get("expires_after_seconds")
	if not (ttl is int or ttl is float) or not is_finite(float(ttl)) or ttl != floor(float(ttl)) or ttl < 0 or ttl > 90: return false
	return (value.partner_joined or not value.partner_online) and (ttl > 0 if value.partner_online else ttl == 0)

static func retry_delay(result: Dictionary) -> int:
	return clampi(int(result.get("retry_after_ms", 0)), 0, 86400000)
