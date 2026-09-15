extends Node
## One registration owner. Push is a hint; authenticated room reads remain authority.
signal changed
signal foreground_hint(route: Dictionary)
signal route_available

const REGISTRATION_PATH := "/v1/notifications/registration"
const RETRY_MS := [5000, 15000, 30000]
var bridge: Node
var status_text := "Turn notifications are off. You can keep playing."
var _api: Node
var _identity: Callable
var _read_binding: Callable
var _write_binding: Callable
var _preference: Callable
var _save_preference: Callable
var _binding: Dictionary = {}
var _context := ""
var _loaded := false
var _busy := false
var _generation := 0
var _resetting := 0
var _request_permission := false
var _queued := true
var _off_cleared := false
var _invalid_cleared := false
var _reset_next_ms := 0
var _next_ms := 0
var _failures := 0
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

func enabled() -> bool:
	return _preference.is_valid() and _preference.call() == true

func busy() -> bool:
	return _busy or _resetting > 0

func registered() -> bool:
	return enabled() and not _last_registration.is_empty()

func set_enabled(value: bool) -> bool:
	if not _save_preference.is_valid() or _save_preference.call(value) != true:
		_status("This setting could not be saved. Please try again.")
		return false
	_generation += 1
	_request_permission = value
	_last_registration = ""
	_route = {}
	_acked.clear()
	_off_cleared = not value
	queue_reconcile()
	if not value:
		_reset_native("disable")
		_status("Turn notifications are off. You can keep playing.")
	else:
		_status("Checking Android notification permission…")
	return true

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
	if not enabled() and not _off_cleared and now_ms >= _reset_next_ms:
		_off_cleared = true
		_reset_native("disable")
		return
	if enabled(): _off_cleared = false
	# Keep a cold-launch route during the initial Keystore read. A settled
	# missing/failed/recovery identity cannot authorize its old native binding.
	if key.is_empty():
		if identity.get("settled", false) and not _invalid_cleared:
			_invalid_cleared = true
			_reset_native("clear_binding")
		if enabled(): _status("Open an online room with your saved identity to finish enabling notifications.")
		return
	if busy() or not network_idle or _api.busy or now_ms < _next_ms: return
	if not _queued: return
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
			_fail(now_ms, "The notification binding could not be read securely. Gameplay is unaffected.")
			return
		var value: Dictionary = saved.value
		if not value.is_empty() and not valid_binding(value):
			_fail(now_ms, "The saved notification binding is unsupported. It has been kept unchanged.")
			return
		_binding = value.duplicate(true)
		_loaded = true
		if not _binding.is_empty() and binding_key(_binding) != key:
			await bridge.call_native("clear_binding")
			if not _current(generation, key): return
			_binding = {}
	if not enabled():
		await _unregister(generation, key, now_ms)
		return
	var operation := "request_permission" if _request_permission else "status"
	_request_permission = false
	var native: Dictionary = await bridge.call_native(operation)
	if not _current(generation, key): return
	if not native.get("ok", false) or not native.get("data") is Dictionary:
		_fail(now_ms, "Turn notifications are unavailable in this build. You can keep playing.")
		return
	var status: Dictionary = native.data
	if status.get("supported") != true or status.get("configured") != true:
		_status("Turn notifications are not configured in this build. You can keep playing.")
		return
	if status.get("opted_in") != true or status.get("permission_granted") != true or status.get("channel_enabled") != true:
		_last_registration = ""
		_status("Notifications are off in Android. Enable them in Android settings, then try again here; gameplay is unaffected.")
		return
	if _binding.is_empty():
		var identity: Dictionary = _identity.call()
		var next := {"schema_version": 1, "owner": identity.owner, "credential_hash": identity.credential_hash, "binding_epoch": _new_epoch()}
		var stored: Dictionary = await _write_binding.call(next)
		if not _current(generation, key): return
		if not stored.get("ok", false):
			_fail(now_ms, "The notification binding could not be secured. Nothing was registered.")
			return
		_binding = next
	# Cold-start routing is read only after the saved credential binding matches.
	await _read_route(generation, key)
	if not _current(generation, key): return
	var token_result: Dictionary = await bridge.call_native("get_token")
	if not _current(generation, key): return
	var token_data: Variant = token_result.get("data")
	if not token_result.get("ok", false) or not token_data is Dictionary or not valid_token(token_data.get("token")) or not _integer(token_data.get("generation")):
		_fail(now_ms, "Android could not prepare notifications. We will try again; you can keep playing.")
		return
	var registration := str(_binding.binding_epoch) + ":" + str(token_data.token).sha256_text() + ":" + str(token_data.generation)
	if registration == _last_registration and status.get("registration_pending") != true:
		_status("Turn notifications are on for this device.")
		return
	var epoch: String = _binding.binding_epoch
	var response: Dictionary = await _api.request_json(HTTPClient.METHOD_POST, REGISTRATION_PATH, {"schema_version": 1, "token": token_data.token, "binding_epoch": epoch})
	if not _current(generation, key): return
	var ack: Variant = response.get("data")
	if not response.get("ok", false) or not ack is Dictionary or ack.get("registered") != true or ack.get("binding_epoch") != epoch:
		_fail(now_ms, "Turn notifications could not be registered yet. Your room and drafts are unchanged.", int(response.get("retry_after_ms", 0)))
		return
	var bound: Dictionary = await bridge.call_native("set_binding", [epoch, token_data.token, int(token_data.generation)])
	if not _current(generation, key): return
	var result: Variant = bound.get("data")
	if not bound.get("ok", false) or not result is Dictionary or result.get("bound") != true or result.get("binding_epoch") != epoch or result.get("generation") != token_data.generation:
		_fail(now_ms, "The device token changed while enabling notifications. We will check it again.")
		return
	_last_registration = registration
	_failures = 0
	_status("Turn notifications are on for this device.")
	await _read_route(generation, key)

func _unregister(generation: int, key: String, now_ms: int) -> void:
	if _binding.is_empty(): return
	var response: Dictionary = await _api.request_json(HTTPClient.METHOD_DELETE, REGISTRATION_PATH, {"schema_version": 1, "binding_epoch": _binding.binding_epoch})
	if not _current(generation, key): return
	var ack: Variant = response.get("data")
	if not response.get("ok", false) or not ack is Dictionary or ack.get("unregistered") != true:
		_fail(now_ms, "Notifications are off on this device. Service cleanup will retry when connected.", int(response.get("retry_after_ms", 0)))
		return
	var stored: Dictionary = await _write_binding.call({})
	if not _current(generation, key): return
	if stored.get("ok", false): _binding = {}
	else: _fail(now_ms, "Notifications are off. Saving the cleanup result will retry.")

func _read_route(generation: int, key: String) -> void:
	_route_sequence += 1
	var sequence := _route_sequence
	var response: Dictionary = await bridge.call_native("pending_route")
	if sequence != _route_sequence or not _current(generation, key) or not enabled(): return
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
	return enabled() and valid_route(route) and not _binding.is_empty() and binding_key(_binding) == identity_key(_identity.call()) and route.binding_epoch == _binding.binding_epoch

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
	if not value is Dictionary or value.size() != 7: return false
	for key: String in ["schema_version", "event_id", "kind", "room_id", "room_family", "revision", "binding_epoch"]:
		if not value.get(key) is String: return false
	return value.schema_version == "1" and value.kind == "turn_ready" and value.room_family in ["legacy", "relay"] and _matches(value.room_id, "^[A-Za-z0-9_-]{22}$") and _matches(value.binding_epoch, "^[A-Za-z0-9_-]{22}$") and _matches(value.event_id, "^[A-Za-z0-9_-]{16,128}$") and _matches(value.revision, "^[1-9][0-9]{0,15}$") and int(value.revision) <= 9007199254740991

static func valid_token(value: Variant) -> bool:
	return value is String and value.length() >= 16 and value.length() <= 4096 and _matches(value, "^[!-~]+$")

static func _integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and value >= 0 and value <= 9007199254740991

static func _matches(value: Variant, pattern: String) -> bool:
	return value is String and RegEx.create_from_string(pattern).search(value) != null

static func _new_epoch() -> String:
	return Marshalls.raw_to_base64(Crypto.new().generate_random_bytes(16)).replace("+", "-").replace("/", "_").trim_suffix("==")
