extends Node
const PlayerCopy = preload("res://presentation/player_copy.gd")
## One registration owner. Push is a hint; authenticated room reads remain authority.
signal changed
signal foreground_hint(route: Dictionary)
signal route_available

const REGISTRATION_PATH := "/v1/notifications/registration"
const CATEGORIES_PATH := "/v1/notifications/categories"
const RETRY_MS := [5000, 15000, 30000]
# A server without the categories endpoint answers 404; back off without touching turn status.
const CATEGORY_RETRY_MS := [15000, 60000, 300000]
var bridge: Node
var status_text := PlayerCopy.TURN_NOTIFICATIONS_1875CCB77FB2
var _api: Node
var _identity: Callable
var _read_binding: Callable
var _write_binding: Callable
var _preference: Callable
var _hosting_preference: Callable
var _save_hosting_preference: Callable
var _save_preference: Callable
var _request_preference: Callable
var _save_request_preference: Callable
# Redo-request push is a server-side opt-in per binding epoch: epoch -> last value the server confirmed.
# Missing means unknown, so each binding is confirmed once per session.
var _request_categories: Dictionary = {}
## A confirmed opt-out is also kept across launches, by a digest of its binding
## epoch, so a launch with the option off sends nothing. An opt-in is still
## confirmed once per session: the server drops it with a lapsed registration.
var categories_path := "user://notification-categories.json"
## Identities already asked for phone permission after their hosting alerts came back.
var permission_asked_path := "user://hosting-permission-asked.cfg"
var _confirmed_off := ""
var _confirmed_off_loaded := false
# The registration on which the server answered 404 to an opt-in: no route
# there, so the option waits for a new registration or a change of option.
var _category_parked := ""
var _category_next_ms := 0
var _category_failures := 0
var _category_busy := false
var _binding: Dictionary = {}
var _context := ""
var _loaded := false
var _busy := false
var _generation := 0
var _resetting := 0
var _request_permission := false
var _opt_in_restored := false
var _queued := true
var _off_cleared := false
var _invalid_cleared := false
var _reset_next_ms := 0
var _next_ms := 0
var _failures := 0
var _turn_channel_ready := false
var _hosting_channel_ready := false
var _last_registration := ""
var _route: Dictionary = {}
var _route_sequence := 0
var _acked: Array[String] = []

func configure(api: Node, native_bridge: Node, identity: Callable, read_binding: Callable, write_binding: Callable, preference: Callable, save_preference: Callable) -> void:
	_api = api
	bridge = native_bridge
	_identity = identity
	_read_binding = read_binding
	_write_binding = write_binding
	_preference = preference
	_save_preference = save_preference
	bridge.token_changed.connect(queue_reconcile)
	bridge.received.connect(_received)

func configure_hosting(read_preferences: Callable, save_preferences: Callable) -> void:
	_hosting_preference = read_preferences
	_save_hosting_preference = save_preferences
	queue_reconcile()

func configure_requests(read_preference: Callable, save_preference: Callable) -> void:
	_request_preference = read_preference
	_save_request_preference = save_preference

## A sub-option of turn notifications: it never registers, asks for permission or changes turn status.
func requests_enabled() -> bool:
	return enabled() and _request_preference.is_valid() and _request_preference.call() == true

func set_requests_enabled(value: bool) -> bool:
	if not _save_request_preference.is_valid() or _save_request_preference.call(value) != true: return false
	_category_next_ms = 0
	_category_failures = 0
	_category_parked = ""
	_sync_native_categories()
	return true

func _hosting_key() -> String:
	return str(_api.base_url).trim_suffix("/") + ":" + identity_key(_identity.call()) if is_instance_valid(_api) and _identity.is_valid() else ""

func _hosting_ids() -> Dictionary:
	if not _hosting_preference.is_valid() or identity_key(_identity.call()).is_empty(): return {}
	var saved: Variant = _hosting_preference.call()
	return saved.get(_hosting_key(),{}).duplicate(true) if saved is Dictionary and saved.get(_hosting_key(),{}) is Dictionary else {}

func hosting_enabled() -> bool:
	return not _hosting_ids().is_empty()

func _transport_enabled() -> bool:
	return enabled() or hosting_enabled()

func set_hosting_friend(player_id: String, value: bool, request_id: String = "", request_permission: bool = true) -> bool:
	if not _save_hosting_preference.is_valid() or not _matches(player_id,"^[A-Za-z0-9_-]{22}$") or identity_key(_identity.call()).is_empty(): return false
	var saved: Variant = _hosting_preference.call()
	if not saved is Dictionary: saved = {}
	var next: Dictionary = saved.duplicate(true)
	var peers := _hosting_ids()
	if value: peers[player_id] = request_id
	else: peers.erase(player_id)
	next[_hosting_key()] = peers
	if _save_hosting_preference.call(next) != true: return false
	_generation += 1
	_sync_native_categories()
	_request_permission = value and request_permission
	_last_registration = ""
	queue_reconcile()
	if not _transport_enabled(): _off_cleared = false
	return true

func sync_hosting_preferences(preferences: Array) -> void:
	var peers := _hosting_ids()
	var restored := false
	for item: Variant in preferences:
		if item is Dictionary and item.get("enabled") == true:
			peers.erase(str(item.player_id))
			if _hosting_ids().get(str(item.player_id)) != str(item.request_id):
				restored = restored or not _hosting_ids().has(str(item.player_id))
				set_hosting_friend(str(item.player_id),true,str(item.request_id),false)
	for player_id: String in peers: set_hosting_friend(player_id,false,"",false)
	if restored: _ask_hosting_permission_once()

## Hosting alerts the server kept came back to a phone that had none saved (a
## reinstall), so Android permission may be missing. This runs while Friends is
## open; ask through the usual permission flow once per identity, never again.
func _ask_hosting_permission_once() -> void:
	var key := _hosting_key()
	if key.is_empty() or not hosting_enabled() or hosting_registered(): return
	var asked := ConfigFile.new()
	asked.load(permission_asked_path)
	var section := key.sha256_text()
	if asked.get_value(section,"asked",false) == true: return
	asked.set_value(section,"asked",true)
	if asked.save(permission_asked_path) != OK: return
	_request_permission = true
	queue_reconcile()

func enabled() -> bool:
	return _preference.is_valid() and _preference.call() == true

func busy() -> bool:
	return _busy or _resetting > 0

func registered() -> bool:
	return enabled() and _turn_channel_ready and not _last_registration.is_empty()

func hosting_registered() -> bool:
	return hosting_enabled() and _hosting_channel_ready and not _last_registration.is_empty()

func set_enabled(value: bool) -> bool:
	if not _save_preference.is_valid() or _save_preference.call(value) != true:
		_status(PlayerCopy.MAIN_34B82590B663)
		return false
	_generation += 1
	_sync_native_categories()
	_request_permission = value
	_last_registration = ""
	_route = {}
	_acked.clear()
	_off_cleared = not value
	queue_reconcile()
	if not value and not hosting_enabled():
		_reset_native("disable")
		_status(PlayerCopy.TURN_NOTIFICATIONS_1875CCB77FB2)
	else:
		_status(PlayerCopy.TURN_NOTIFICATIONS_6B57E7FA9822)
	return true

func _sync_native_categories() -> void:
	# Category opt-out is local and must take effect even while the app is
	# backgrounded or a network request prevents registration reconciliation.
	var generation := _generation
	var key := identity_key(_identity.call())
	var result: Dictionary = await bridge.call_native("set_categories",[enabled(),hosting_enabled(),requests_enabled()])
	if generation != _generation or key != identity_key(_identity.call()): return
	if not result.get("ok",false) or result.get("data",{}).get("updated") != true:
		_fail(Time.get_ticks_msec(),PlayerCopy.TURN_NOTIFICATIONS_3ACFC48F089A)

func queue_reconcile() -> void:
	_queued = true
	_next_ms = 0

func invalidate_identity() -> void:
	_generation += 1
	_context = ""
	_loaded = false
	_binding = {}
	_last_registration = ""
	_route = {}
	_acked.clear()
	_request_categories = {}
	_category_next_ms = 0
	_category_failures = 0
	_category_parked = ""
	_reset_native("clear_binding")
	queue_reconcile()

func _reset_native(operation: String) -> void:
	_resetting += 1
	changed.emit()
	var result: Dictionary = await bridge.call_native(operation)
	_resetting -= 1
	if operation == "disable" and (not result.get("ok", false) or result.get("data", {}).get("token_deleted") != true):
		_off_cleared = false
		_reset_next_ms = Time.get_ticks_msec() + 30000
	changed.emit()

func service(now_ms: int, foreground: bool, network_idle: bool) -> void:
	if not is_inside_tree() or not foreground or busy(): return
	var identity: Dictionary = _identity.call()
	var key := identity_key(identity)
	if key != _context:
		_generation += 1
		if not _context.is_empty(): _reset_native("clear_binding")
		_context = key
		_loaded = false
		_binding = {}
		_last_registration = ""
		_route = {}
		_invalid_cleared = false
		queue_reconcile()
	# Hosting consent is per identity, so it is unknown until the identity read
	# settles. Deciding "off" earlier switched phone notifications off on every
	# cold start for a player with hosting alerts but no turn notifications.
	if not _transport_enabled() and not _off_cleared and now_ms >= _reset_next_ms and (not key.is_empty() or identity.get("settled", false)):
		_off_cleared = true
		_reset_native("disable")
		return
	if _transport_enabled(): _off_cleared = false
	# Keep a cold-launch route during the initial Keystore read. A settled
	# missing/failed/recovery identity cannot authorize its old native binding.
	if key.is_empty():
		if identity.get("settled", false) and not _invalid_cleared:
			_invalid_cleared = true
			_reset_native("clear_binding")
		if _transport_enabled(): _status(PlayerCopy.TURN_NOTIFICATIONS_F360625134B7)
		return
	if busy() or not network_idle or _api.busy or now_ms < _next_ms: return
	if not _queued:
		if _category_due(now_ms):
			_busy = true
			changed.emit()
			await _sync_request_category(_generation, key, now_ms)
			_busy = false
			changed.emit()
		return
	_busy = true
	changed.emit()
	await _reconcile(_generation, key, now_ms)
	_busy = false
	changed.emit()

func _reconcile(generation: int, key: String, now_ms: int) -> void:
	_queued = false
	if not _loaded:
		var saved: Dictionary = await _read_binding.call()
		if not _current(generation, key): return
		if not saved.get("ok", false) or not saved.get("value") is Dictionary:
			_fail(now_ms, PlayerCopy.TURN_NOTIFICATIONS_93F91B5297EC)
			return
		var value: Dictionary = saved.value
		if not value.is_empty() and not valid_binding(value):
			_fail(now_ms, PlayerCopy.TURN_NOTIFICATIONS_EBCCF05667BE)
			return
		_binding = value.duplicate(true)
		_loaded = true
		if not _binding.is_empty() and binding_key(_binding) != key:
			await bridge.call_native("clear_binding")
			if not _current(generation, key): return
			_binding = {}
	if not _transport_enabled():
		await _unregister(generation, key, now_ms)
		return
	var categories: Dictionary = await bridge.call_native("set_categories",[enabled(),hosting_enabled(),requests_enabled()])
	if not _current(generation,key): return
	if not categories.get("ok",false) or categories.get("data",{}).get("updated") != true:
		_fail(now_ms,PlayerCopy.TURN_NOTIFICATIONS_3ACFC48F089A)
		return
	var operation := "request_permission" if _request_permission else "status"
	_request_permission = false
	var native: Dictionary = await bridge.call_native(operation)
	if not _current(generation, key): return
	if not native.get("ok", false) or not native.get("data") is Dictionary:
		_fail(now_ms, PlayerCopy.TURN_NOTIFICATIONS_3ACFC48F089A)
		return
	var status: Dictionary = native.data
	# A saved opt-in whose native flag was cleared (0.6.0 did that on cold
	# starts) comes back without a dialog: Android permission is still granted.
	if operation == "status" and not _opt_in_restored and status.get("opted_in") != true and status.get("permission_granted") == true and status.get("configured") == true:
		_opt_in_restored = true
		var restored: Dictionary = await bridge.call_native("request_permission")
		if not _current(generation, key): return
		if restored.get("ok", false) and restored.get("data") is Dictionary: status = restored.data
	_turn_channel_ready = status.get("permission_granted") == true and status.get("channel_enabled") == true
	_hosting_channel_ready = status.get("permission_granted") == true and status.get("hosting_channel_enabled",status.get("channel_enabled")) == true
	if status.get("supported") != true or status.get("configured") != true:
		_status(PlayerCopy.TURN_NOTIFICATIONS_F3CB97B22B0F)
		return
	if status.get("opted_in") != true or status.get("permission_granted") != true or (not enabled() or status.get("channel_enabled") != true) and (not hosting_enabled() or status.get("hosting_channel_enabled",status.get("channel_enabled")) != true):
		_last_registration = ""
		_status(PlayerCopy.TURN_NOTIFICATIONS_5015371169FE)
		return
	if _binding.is_empty():
		var identity: Dictionary = _identity.call()
		var next := {"schema_version": 1, "owner": identity.owner, "credential_hash": identity.credential_hash, "binding_epoch": _new_epoch()}
		var stored: Dictionary = await _write_binding.call(next)
		if not _current(generation, key): return
		if not stored.get("ok", false):
			_fail(now_ms, PlayerCopy.TURN_NOTIFICATIONS_1DA0D2B61934)
			return
		_binding = next
	# Cold-start routing is read only after the saved credential binding matches.
	await _read_route(generation, key)
	if not _current(generation, key): return
	var token_result: Dictionary = await bridge.call_native("get_token")
	if not _current(generation, key): return
	var token_data: Variant = token_result.get("data")
	if not token_result.get("ok", false) or not token_data is Dictionary or not valid_token(token_data.get("token")) or not _integer(token_data.get("generation")):
		_fail(now_ms, PlayerCopy.TURN_NOTIFICATIONS_3B300B883B57)
		return
	var registration := str(_binding.binding_epoch) + ":" + str(token_data.token).sha256_text() + ":" + str(token_data.generation)
	if registration == _last_registration and status.get("registration_pending") != true:
		_status(PlayerCopy.TURN_NOTIFICATIONS_D05B75D3C933)
		await _sync_request_category(generation, key, now_ms)
		return
	var epoch: String = _binding.binding_epoch
	var response: Dictionary = await _api.request_json(HTTPClient.METHOD_POST, REGISTRATION_PATH, {"schema_version": 1, "token": token_data.token, "binding_epoch": epoch})
	if not _current(generation, key): return
	var ack: Variant = response.get("data")
	if not response.get("ok", false) or not ack is Dictionary or ack.get("registered") != true or ack.get("binding_epoch") != epoch:
		_fail(now_ms, PlayerCopy.TURN_NOTIFICATIONS_F20AF0DE21A8, int(response.get("retry_after_ms", 0)))
		return
	var bound: Dictionary = await bridge.call_native("set_binding", [epoch, token_data.token, int(token_data.generation)])
	if not _current(generation, key): return
	var result: Variant = bound.get("data")
	if not bound.get("ok", false) or not result is Dictionary or result.get("bound") != true or result.get("binding_epoch") != epoch or result.get("generation") != token_data.generation:
		_fail(now_ms, PlayerCopy.TURN_NOTIFICATIONS_9BF0800B5B39)
		return
	_last_registration = registration
	_failures = 0
	_status(PlayerCopy.TURN_NOTIFICATIONS_D05B75D3C933)
	await _read_route(generation, key)
	if not _current(generation, key): return
	await _sync_request_category(generation, key, now_ms)

func _category_due(now_ms: int) -> bool:
	if _category_busy or not _request_preference.is_valid() or _binding.is_empty() or _last_registration.is_empty() or now_ms < _category_next_ms: return false
	# An opt-out that never reached the server must not outlive a restart.
	var epoch := str(_binding.binding_epoch)
	var desired := requests_enabled()
	if desired and _category_parked == _last_registration: return false
	if _request_categories.has(epoch): return _request_categories[epoch] != desired
	return desired or _saved_off() != epoch.sha256_text()

func _sync_request_category(generation: int, key: String, now_ms: int) -> void:
	if not _category_due(now_ms) or _api.busy: return
	var epoch: String = _binding.binding_epoch
	var desired := requests_enabled()
	_category_busy = true
	var response: Dictionary = await _api.request_json(HTTPClient.METHOD_POST, CATEGORIES_PATH, {"schema_version": 1, "binding_epoch": epoch, "redo_requests": desired})
	_category_busy = false
	if not _current(generation, key): return
	var ack: Variant = response.get("data")
	if response.get("ok", false) and ack is Dictionary and ack.size() == 3 and ack.get("schema_version") == 1 and ack.get("binding_epoch") == epoch and ack.get("redo_requests") == desired:
		_request_categories[epoch] = desired
		_category_failures = 0
		_save_off(epoch if not desired else "")
		return
	if int(response.get("status", 0)) == 404:
		_category_failures = 0
		if desired:
			# A server without this route: asking again at the backoff cannot help.
			_category_parked = _last_registration
			return
		# No registration, or a server without this route: neither can hold an opt-in.
		_request_categories[epoch] = false
		_save_off(epoch)
		return
	# Turn registration and status_text stay as they are; only this option waits.
	_category_failures = mini(_category_failures + 1, CATEGORY_RETRY_MS.size())
	_category_next_ms = maxi(Time.get_ticks_msec(), now_ms) + maxi(int(CATEGORY_RETRY_MS[_category_failures - 1]), clampi(int(response.get("retry_after_ms", 0)), 0, 86400000))

func _saved_off() -> String:
	if not _confirmed_off_loaded:
		_confirmed_off_loaded = true
		var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(categories_path)) if FileAccess.file_exists(categories_path) else null
		var digest: Variant = value.get("confirmed_off") if value is Dictionary and value.size() == 2 and value.get("schema_version") == 1 else null
		_confirmed_off = digest if digest is String and digest.length() == 64 and digest.is_valid_hex_number(false) else ""
	return _confirmed_off

func _save_off(epoch: String) -> void:
	var digest := epoch.sha256_text() if not epoch.is_empty() else ""
	if _saved_off() == digest: return
	var body := JSON.stringify({"schema_version": 1, "confirmed_off": digest})
	var file := FileAccess.open(categories_path + ".tmp", FileAccess.WRITE)
	if file == null: return
	file.store_string(body)
	file.close()
	if DirAccess.rename_absolute(categories_path + ".tmp", categories_path) == OK: _confirmed_off = digest

func _unregister(generation: int, key: String, now_ms: int) -> void:
	if _binding.is_empty(): return
	var response: Dictionary = await _api.request_json(HTTPClient.METHOD_DELETE, REGISTRATION_PATH, {"schema_version": 1, "binding_epoch": _binding.binding_epoch})
	if not _current(generation, key): return
	var ack: Variant = response.get("data")
	if not response.get("ok", false) or not ack is Dictionary or ack.get("unregistered") != true:
		_fail(now_ms, PlayerCopy.TURN_NOTIFICATIONS_A304E7C06EFD, int(response.get("retry_after_ms", 0)))
		return
	var stored: Dictionary = await _write_binding.call({})
	if not _current(generation, key): return
	if stored.get("ok", false): _binding = {}
	else: _fail(now_ms, PlayerCopy.TURN_NOTIFICATIONS_5EE708F03FC4)

func _read_route(generation: int, key: String) -> void:
	_route_sequence += 1
	var sequence := _route_sequence
	var response: Dictionary = await bridge.call_native("pending_route")
	if sequence != _route_sequence or not _current(generation, key) or not _transport_enabled(): return
	var route: Variant = response.get("data", {}).get("route")
	if response.get("ok", false) and route is Dictionary and route.is_empty():
		_route = {}
		return
	if response.get("ok", false) and accepts(route) and route.event_id not in _acked:
		if _route != route:
			_route = route.duplicate(true)
			route_available.emit()

func refresh_pending_route() -> void:
	if not _binding.is_empty():
		await _read_route(_generation, identity_key(_identity.call()))

func pending_route() -> Dictionary:
	return _route.duplicate(true) if accepts(_route) else {}

func acknowledge_route(event_id: String) -> void:
	if _route.get("event_id") != event_id: return
	_route = {}
	_acked.append(event_id)
	if _acked.size() > 32: _acked.pop_front()
	await bridge.call_native("ack_route", [event_id])

func accepts(route: Variant) -> bool:
	return valid_route(route) and (enabled() if route.kind == "turn_ready" else requests_enabled() if route.kind == "redo_requested" else hosting_enabled() and _hosting_ids().has(str(route.host_id))) and not _binding.is_empty() and binding_key(_binding) == identity_key(_identity.call()) and route.binding_epoch == _binding.binding_epoch

func _received(route: Dictionary) -> void:
	if accepts(route): foreground_hint.emit(route.duplicate(true))

func _current(generation: int, key: String) -> bool:
	return is_inside_tree() and generation == _generation and key == identity_key(_identity.call())

func _fail(now_ms: int, message: String, retry_after_ms: int = 0) -> void:
	_failures = mini(_failures + 1, RETRY_MS.size())
	_next_ms = maxi(Time.get_ticks_msec(), now_ms) + maxi(int(RETRY_MS[_failures - 1]), clampi(retry_after_ms, 0, 86400000))
	_queued = true
	_status(message)

func _status(message: String) -> void:
	if status_text == message: return
	status_text = message
	changed.emit()

static func identity_key(identity: Dictionary) -> String:
	if identity.get("ready") != true or not _matches(identity.get("owner"), "^[A-Za-z0-9_-]{22}$") or not _matches(identity.get("credential_hash"), "^[a-f0-9]{64}$"): return ""
	return str(identity.owner) + ":" + str(identity.credential_hash)

static func binding_key(binding: Dictionary) -> String:
	return str(binding.get("owner", "")) + ":" + str(binding.get("credential_hash", ""))

static func valid_binding(value: Dictionary) -> bool:
	return value.size() == 4 and value.get("schema_version") == 1 and _matches(value.get("owner"), "^[A-Za-z0-9_-]{22}$") and _matches(value.get("credential_hash"), "^[a-f0-9]{64}$") and _matches(value.get("binding_epoch"), "^[A-Za-z0-9_-]{22}$")

static func valid_route(value: Variant) -> bool:
	if not value is Dictionary: return false
	var hosting: bool = value.get("kind") == "friend_room_available"
	var keys: Array = ["schema_version","event_id","kind","room_id","room_family","binding_epoch","host_id","publication_epoch"] if hosting else ["schema_version","event_id","kind","room_id","room_family","revision","binding_epoch"]
	if value.size() != keys.size(): return false
	for key: String in keys:
		if not value.get(key) is String: return false
	var sequence: String = value.publication_epoch if hosting else value.revision
	if value.schema_version != "1" or value.kind not in ["turn_ready","friend_room_available","redo_requested"] or value.room_family not in ["legacy","relay"] or not _matches(value.room_id,"^[A-Za-z0-9_-]{22}$") or not _matches(value.binding_epoch,"^[A-Za-z0-9_-]{22}$") or not _matches(value.event_id,"^[A-Za-z0-9_-]{16,128}$") or not _matches(sequence,"^[1-9][0-9]{0,15}$") or int(sequence) > 9007199254740991: return false
	if value.kind == "redo_requested" and not _matches(value.event_id,"^redo_[a-f0-9]{64}$"): return false
	return not hosting or (_matches(value.host_id,"^[A-Za-z0-9_-]{22}$") and value.event_id == value.host_id + "_" + sequence)

static func valid_token(value: Variant) -> bool:
	return value is String and value.length() >= 16 and value.length() <= 4096 and _matches(value, "^[!-~]+$")

static func _integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and value >= 0 and value <= 9007199254740991

## Compiled once per pattern: service() checks identities every frame.
static var _compiled: Dictionary = {}

static func _matches(value: Variant, pattern: String) -> bool:
	if not value is String: return false
	var expression: RegEx = _compiled.get(pattern)
	if expression == null:
		expression = RegEx.create_from_string(pattern)
		_compiled[pattern] = expression
	return expression.search(value) != null

static func _new_epoch() -> String:
	return Marshalls.raw_to_base64(Crypto.new().generate_random_bytes(16)).replace("+", "-").replace("/", "_").trim_suffix("==")
