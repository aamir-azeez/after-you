extends Node
## Owner/credential-scoped tester receipts. Never stores or logs redemption codes.

const Secrets = preload("res://services/secure_store.gd")
const RoomsApi = preload("res://services/rooms_api.gd")
const LIMIT_MS := 60000
var secret_factory: Callable
var api_factory: Callable
var _secrets: Node
var _waiting: Dictionary = {}
var _results: Dictionary = {}
var _generation := 0
var _deadline := 0
var _busy := false
var _binding := ""
var _loaded := false
var _receipt: Dictionary = {}
var _writing_name := ""

func load_cached(base_url: String, expected_owner: String = "") -> Dictionary:
	return await _run("cache", base_url, expected_owner)

func redeem(base_url: String, expected_owner: String, code: String) -> Dictionary:
	return await _run("redeem", base_url, expected_owner, code)

func restore(base_url: String, expected_owner: String) -> Dictionary:
	return await _run("restore", base_url, expected_owner)

func active(base_url: String, owner: String, device_token: String) -> bool:
	var name := _scope(base_url, owner, device_token)
	return not name.is_empty() and name == _binding and _loaded and not _receipt.is_empty()

func cache_loaded_for(base_url: String, owner: String, device_token: String) -> bool:
	var name := _scope(base_url, owner, device_token)
	return not name.is_empty() and name == _binding and _loaded

func invalidate() -> void:
	_generation += 1
	_binding = ""
	_loaded = false
	_receipt.clear()
	# An issued native put may finish after cancellation. The plugin's shared
	# storageExecutor is FIFO: removing the exact old key follows that put.
	if not _writing_name.is_empty() and is_instance_valid(_secrets):
		_secrets.remove_secret(_writing_name)
		_writing_name = ""

func erase_binding(base_url: String, owner: String, device_token: String) -> Dictionary:
	var name := _scope(base_url, owner, device_token)
	if name.is_empty(): return _error("invalid_binding")
	# Explicit cleanup may target the former credential after confirmed deletion;
	# it never needs that deleted identity to authenticate again.
	invalidate()
	if _busy: return _error("service_busy")
	_busy = true
	_deadline = Time.get_ticks_msec() + LIMIT_MS
	var result: Dictionary = await _secret("remove", name, "", _generation)
	_busy = false
	if not _ack(result, "removed"): return _error("storage_unavailable")
	return {"ok":true,"granted":false,"durable":true}

func _run(operation: String, base_url: String, expected_owner: String, code: String = "") -> Dictionary:
	if _busy: return _error("service_busy")
	var authority := _authority(base_url)
	if authority.is_empty() or (not expected_owner.is_empty() and not _owner(expected_owner)): return _error("invalid_binding")
	if operation != "cache" and not _owner(expected_owner): return _error("invalid_binding")
	if operation == "redeem" and RegEx.create_from_string("^[!-~]{8,128}$").search(code) == null: return _error("invalid_tester_request")
	_busy = true
	_generation += 1
	_deadline = Time.get_ticks_msec() + LIMIT_MS
	var result: Dictionary = await _bound(operation, authority, expected_owner, code, _generation)
	code = ""
	_busy = false
	return result

func _bound(operation: String, authority: String, expected_owner: String, code: String, generation: int) -> Dictionary:
	var before: Dictionary = await _identity(generation)
	if not _current(generation): return _error("cancelled")
	if before.is_empty() or (not expected_owner.is_empty() and before.player_id != expected_owner):
		invalidate()
		return _error("identity_changed")
	var owner: String = before.player_id
	var name := _scope(authority, owner, before.device_token)
	if operation == "cache":
		var saved: Dictionary = await _secret("get", name, "", generation)
		if not await _unchanged(before, generation): return _error("identity_changed")
		if not _get_result(saved): return _error("storage_unavailable")
		var receipt: Dictionary = {}
		if saved.found:
			if not saved.value is String or saved.value.to_utf8_buffer().size() > 4096: return _error("invalid_cached_grant")
			var parser := JSON.new()
			if parser.parse(saved.value) != OK or not parser.data is Dictionary: return _error("invalid_cached_grant")
			var envelope: Dictionary = parser.data
			if not _exact(envelope, ["schema_version","authority","player_id","credential_hash","receipt"]) or not _schema_one(envelope.get("schema_version")) or envelope.get("authority") != authority or envelope.get("player_id") != owner or envelope.get("credential_hash") != before.device_token.sha256_text(): return _error("invalid_cached_grant")
			if not envelope.get("receipt") is Dictionary or not _grant(envelope.receipt, owner): return _error("invalid_cached_grant")
			receipt = envelope.receipt.duplicate(true)
		_binding = name
		_loaded = true
		_receipt = receipt
		return {"ok":true,"granted":not receipt.is_empty(),"durable":true}
	var api: Node = api_factory.call() if api_factory.is_valid() else RoomsApi.new()
	api.base_url = authority
	api.player_id = owner
	api.device_token = before.device_token
	add_child(api)
	var response: Dictionary = await api.request_json(HTTPClient.METHOD_POST if operation == "redeem" else HTTPClient.METHOD_GET, "/v1/tester-access", {"schema_version":1,"code":code} if operation == "redeem" else {})
	code = ""
	api.player_id = ""
	api.device_token = ""
	api.queue_free()
	if not await _unchanged(before, generation): return _error("identity_changed")
	if response.get("ok") != true or response.get("status") != 200:
		return _error(_response_code(response), name)
	var data: Variant = response.get("data")
	if not data is Dictionary: return _error("invalid_tester_response", name)
	if _no_grant(data, owner):
		# A permanent locally verified grant is not revoked by an optional request.
		if name == _binding and not _receipt.is_empty(): return _error("tester_state_mismatch", name)
		_binding = name
		_loaded = true
		_receipt.clear()
		return {"ok":true,"granted":false,"durable":true}
	if not _grant(data, owner): return _error("invalid_tester_response", name)
	if name == _binding and _loaded and _receipt == data: return {"ok":true,"granted":true,"durable":true}
	var envelope := {"schema_version":1,"authority":authority,"player_id":owner,"credential_hash":before.device_token.sha256_text(),"receipt":data.duplicate(true)}
	_writing_name = name
	var stored: Dictionary = await _secret("put", name, JSON.stringify(envelope), generation)
	if not await _unchanged(before, generation):
		_queue_old_remove(name)
		return _error("identity_changed")
	if not _ack(stored, "stored"):
		_queue_old_remove(name)
		return _error("storage_unavailable", name)
	_writing_name = ""
	_binding = name
	_loaded = true
	_receipt = data.duplicate(true)
	return {"ok":true,"granted":true,"durable":true}

func _unchanged(before: Dictionary, generation: int) -> bool:
	if not _current(generation): return false
	var after: Dictionary = await _identity(generation)
	if not _current(generation): return false
	if after != before:
		invalidate()
		return false
	return true

func _queue_old_remove(name: String) -> void:
	if is_instance_valid(_secrets): _secrets.remove_secret(name)
	if _writing_name == name: _writing_name = ""

func _identity(generation: int) -> Dictionary:
	var recovery: Dictionary = await _secret("get", "recovery_pending", "", generation)
	if not _current(generation) or not _get_result(recovery) or recovery.found: return {}
	var saved: Dictionary = await _secret("get", "player_identity", "", generation)
	if not _current(generation) or not _get_result(saved) or not saved.found or not saved.value is String or saved.value.to_utf8_buffer().size() > 4096: return {}
	var parser := JSON.new()
	if parser.parse(saved.value) != OK or not parser.data is Dictionary: return {}
	var value: Dictionary = parser.data
	if not value.get("player_id") is String or not value.get("device_token") is String or not _owner(value.player_id) or not _token(value.device_token): return {}
	return {"player_id":value.player_id,"device_token":value.device_token}

func _secret(operation: String, name: String, value: String, generation: int) -> Dictionary:
	if not _current(generation): return {}
	if not is_instance_valid(_secrets):
		_secrets = secret_factory.call() if secret_factory.is_valid() else Secrets.new()
		add_child(_secrets)
		_secrets.completed.connect(func(id: String, op: String, payload: Dictionary):
			if _waiting.get(id) == op: _results[id] = payload.duplicate(true))
		_secrets.failed.connect(func(id: String, op: String, _code: String):
			if _waiting.get(id) == op: _results[id] = {})
	var id: String
	match operation:
		"get": id = _secrets.get_secret(name)
		"put": id = _secrets.put_secret(name, value)
		"remove": id = _secrets.remove_secret(name)
	_waiting[id] = operation
	var deadline := mini(_deadline, Time.get_ticks_msec() + 10000)
	while _current(generation) and not _results.has(id) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var result: Dictionary = _results.get(id, {}) if _current(generation) else {}
	_results.erase(id)
	_waiting.erase(id)
	return result

func _current(generation: int) -> bool:
	return generation == _generation and is_inside_tree() and Time.get_ticks_msec() < _deadline

func _error(code: String, name: String = "") -> Dictionary:
	var kept := not name.is_empty() and name == _binding and _loaded and not _receipt.is_empty()
	return {"ok":false,"granted":kept,"durable":kept,"code":code}

static func _response_code(response: Dictionary) -> String:
	var code: Variant = response.get("code", "connection_interrupted")
	return code if code is String and code in ["tester_access_unavailable","tester_rate_limited","invalid_tester_request","invalid_auth","rate_limited","service_unavailable","connection_interrupted"] else "connection_interrupted"

static func _get_result(value: Dictionary) -> bool:
	return _exact(value, ["found","value"]) and value.get("found") is bool and ((value.found and value.value is String) or (not value.found and value.value == null))

static func _ack(value: Dictionary, key: String) -> bool:
	return _exact(value, [key]) and value.get(key) is bool and value[key]

static func _schema_one(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT,TYPE_FLOAT] and value == 1

static func _exact(value: Dictionary, keys: Array) -> bool:
	if value.size() != keys.size(): return false
	for key in keys:
		if not value.has(key): return false
	return true

static func _grant(value: Dictionary, owner: String) -> bool:
	return _exact(value, ["schema_version","granted","access_source","entitlement","player_id","granted_at"]) and _schema_one(value.get("schema_version")) and value.get("granted") is bool and value.granted and value.get("access_source") == "tester_grant" and value.get("entitlement") == "full_journey" and value.get("player_id") == owner and _date(value.get("granted_at"))

static func _no_grant(value: Dictionary, owner: String) -> bool:
	return _exact(value, ["schema_version","granted","player_id"]) and _schema_one(value.get("schema_version")) and value.get("granted") is bool and not value.granted and value.get("player_id") == owner

static func _date(value: Variant) -> bool:
	if not value is String or RegEx.create_from_string("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\\.[0-9]{3}Z$").search(value) == null: return false
	var year := int(value.substr(0,4))
	var month := int(value.substr(5,2))
	var day := int(value.substr(8,2))
	if month < 1 or month > 12 or int(value.substr(11,2)) > 23 or int(value.substr(14,2)) > 59 or int(value.substr(17,2)) > 59: return false
	var days := [31,29 if year % 4 == 0 and (year % 100 != 0 or year % 400 == 0) else 28,31,30,31,30,31,31,30,31,30,31]
	return day >= 1 and day <= days[month-1]

static func _owner(value: String) -> bool:
	return RegEx.create_from_string("^[A-Za-z0-9_-]{22}$").search(value) != null

static func _token(value: String) -> bool:
	return RegEx.create_from_string("^[A-Za-z0-9_-]{43}$").search(value) != null

static func _authority(value: String) -> String:
	var match_value := RegEx.create_from_string("^https://([A-Za-z0-9]+(?:[.-][A-Za-z0-9]+)*)(?::([0-9]{1,5}))?/?$").search(value)
	if match_value == null: return ""
	var port := match_value.get_string(2)
	if not port.is_empty() and (int(port) < 1 or int(port) > 65535): return ""
	return "https://" + match_value.get_string(1).to_lower() + (":" + str(int(port)) if not port.is_empty() and int(port) != 443 else "")

static func _scope(base_url: String, owner: String, device_token: String) -> String:
	var authority := _authority(base_url)
	if authority.is_empty() or not _owner(owner) or not _token(device_token): return ""
	return "tester_v1_" + (authority + "\n" + owner + "\n" + device_token.sha256_text()).sha256_text().substr(0,54)

func _exit_tree() -> void:
	invalidate()
	_waiting.clear()
	_results.clear()
