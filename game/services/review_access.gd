extends Node
## Ephemeral authenticated reviewer verification. Never writes an unlock or identity.

const Secrets = preload("res://services/secure_store.gd")
const RoomsApi = preload("res://services/rooms_api.gd")
var secret_factory: Callable
var api_factory: Callable
var _secrets: Node
var _results: Dictionary = {}
var _waiting: Dictionary = {}
var _generation := 0
var _busy := false
var _deadline := 0

func invalidate() -> void:
	_generation += 1

func verify(owner: String, base_url: String) -> bool:
	if _busy or RegEx.create_from_string("^[A-Za-z0-9_-]{22}$").search(owner) == null or not base_url.begins_with("https://"):
		return false
	_busy = true
	_generation += 1
	_deadline = Time.get_ticks_msec() + 30000
	var accepted: bool = await _verify_bound(owner, base_url, _generation)
	_busy = false
	return accepted

func _verify_bound(owner: String, base_url: String, generation: int) -> bool:
	var before: Dictionary = await _identity(generation)
	if not _current(generation) or before.get("player_id") != owner: return false
	var api: Node = api_factory.call() if api_factory.is_valid() else RoomsApi.new()
	api.base_url = base_url
	api.player_id = owner
	api.device_token = before.device_token
	add_child(api)
	var response: Dictionary = await api.request_json(HTTPClient.METHOD_GET, "/v1/entitlement")
	api.player_id = ""
	api.device_token = ""
	api.queue_free()
	if not _current(generation) or not valid_response(response, owner): return false
	var after: Dictionary = await _identity(generation)
	return _current(generation) and after == before

static func valid_response(response: Dictionary, owner: String) -> bool:
	var data: Variant = response.get("data")
	if response.get("ok") != true or response.get("status") != 200 or not data is Dictionary: return false
	return data.get("full_journey") is bool and data.full_journey and data.get("status") == "verified" and data.get("access_source") == "review_grant" and data.get("entitlement") == "full_journey_play" and data.get("player_id") == owner

func _identity(generation: int) -> Dictionary:
	# A queued recovery must finish before using either the old or new credential.
	var recovery: Dictionary = await _read_secret("recovery_pending", generation)
	if not _current(generation) or not recovery.get("found") is bool or recovery.found or recovery.get("value") != null: return {}
	var saved: Dictionary = await _read_secret("player_identity", generation)
	if not _current(generation) or not saved.get("found") is bool or not saved.found or not saved.get("value") is String: return {}
	var parser := JSON.new()
	if parser.parse(saved.value) != OK or not parser.data is Dictionary: return {}
	var identity: Dictionary = parser.data
	if not identity.get("player_id") is String or not identity.get("device_token") is String: return {}
	if RegEx.create_from_string("^[A-Za-z0-9_-]{22}$").search(identity.player_id) == null or RegEx.create_from_string("^[A-Za-z0-9_-]{32,128}$").search(identity.device_token) == null: return {}
	return {"player_id": identity.player_id, "device_token": identity.device_token}

func _read_secret(name: String, generation: int) -> Dictionary:
	if not _current(generation): return {}
	if not is_instance_valid(_secrets):
		_secrets = secret_factory.call() if secret_factory.is_valid() else Secrets.new()
		add_child(_secrets)
		_secrets.completed.connect(func(id: String, operation: String, value: Dictionary):
			if operation == "get" and _waiting.has(id): _results[id] = value)
		_secrets.failed.connect(func(id: String, _operation: String, _code: String):
			if _waiting.has(id): _results[id] = {})
	var id: String = _secrets.get_secret(name)
	_waiting[id] = true
	var deadline := mini(_deadline, Time.get_ticks_msec() + 10000)
	while _current(generation) and not _results.has(id) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var result: Dictionary = _results.get(id, {})
	_results.erase(id)
	_waiting.erase(id)
	return result if _current(generation) else {}

func _current(generation: int) -> bool:
	return generation == _generation and is_inside_tree() and Time.get_ticks_msec() < _deadline

func _exit_tree() -> void:
	invalidate()
	_results.clear()
	_waiting.clear()
