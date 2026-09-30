extends Node
## Process-local provider reads. The broker outlives scene-local facades.
## No saved unlock, polling, store simulation, or server mutation authority.

signal request_result(id: String, operation: String, payload: String)
signal request_error(id: String, operation: String, code: String, message: String, cancelled: bool)
signal customer_info_updated(payload: String)

const PlayerCopy = preload("res://presentation/player_copy.gd")
const ReviewAccess = preload("res://services/review_access.gd")
const READ_TIMEOUT_MS := 30000
const ACTION_TIMEOUT_MS := 180000
const MAX_READERS := 32
static var _shared: WeakRef
var _native: Object
var _scope := ""
var _owner := ""
var _configuration: Dictionary = {}
var _held := true
var _generation := 0
var _identity_generation := 0
var _revision := 0
var _configured := false
var _cache: Dictionary = {}
var _latest: Dictionary = {}
var _read: Dictionary = {}
var _writes: Dictionary = {}
var _waiting_reads: Array[Dictionary] = []

static func shared(tree: SceneTree, native: Object) -> Node:
	var current: Node = _shared.get_ref() if _shared != null else null
	if is_instance_valid(current): return current
	current = load("res://services/purchase_session.gd").new()
	current._native = native
	current._connect_native_signals()
	_shared = weakref(current)
	# Facades can be created during root readiness, while add_child is blocked.
	tree.root.add_child.call_deferred(current)
	return current

static func suspend_shared(clear: bool) -> void:
	var current: Node = _shared.get_ref() if _shared != null else null
	if is_instance_valid(current): current.suspend(clear)

func _ready() -> void:
	# Requests can already be pending before the deferred tree attachment.
	_refresh_processing()

func _connect_native_signals() -> void:
	_native.connect("request_result", _result)
	_native.connect("request_error", _error)
	_native.connect("customer_info_updated", _updated)

func bind_context(configuration: Dictionary, owner: String, token: String) -> void:
	if not _id(owner, 22, 22) or not _id(token, 32, 128):
		suspend(true)
		return
	var scope := JSON.stringify([str(configuration.get("api_base_url", "")).trim_suffix("/"),
		configuration.get("purchase_mode"), configuration.get("entitlement_id"),
		configuration.get("revenuecat_public_key"), owner, token.sha256_text()])
	if scope != _scope:
		suspend(true)
		_scope = scope
		_owner = owner
		_configuration = configuration.duplicate(true)
	_held = false

func suspend(clear: bool) -> void:
	_held = true
	_generation += 1
	_identity_generation += 1
	_cancel_read()
	for id: String in _writes: _fail.call_deferred(id, _writes[id].operation)
	_writes.clear()
	for reader: Dictionary in _waiting_reads: _fail.call_deferred(reader.id, reader.operation)
	_waiting_reads.clear()
	_refresh_processing()
	if clear:
		_scope = ""
		_owner = ""
		_configuration.clear()
		_configured = false
		_cache.clear()
		_latest.clear()
		_revision += 1

func invalidate() -> void:
	_generation += 1
	_revision += 1
	_cache.clear()
	_cancel_read()

func dispatch(id: String, operation: String, arguments: Array, configuration: Dictionary, force: bool = false, identity_generation: int = -1, generation: int = -1) -> void:
	if _held or identity_generation != _identity_generation or not _same_configuration(configuration):
		_fail.call_deferred(id, operation)
		return
	if operation not in ["configure", "get_customer_info"]:
		if not _configured:
			_fail.call_deferred(id, operation)
			return
		if operation in ["purchase_package", "restore_purchases"]:
			if _mutation_pending():
				_fail.call_deferred(id, operation)
				return
			invalidate()
		var timeout_ms := READ_TIMEOUT_MS if operation == "get_offerings" else ACTION_TIMEOUT_MS
		_writes[id] = {"operation": operation, "generation": _identity_generation, "deadline":Time.get_ticks_msec() + timeout_ms}
		_refresh_processing()
		_native.callv(operation, arguments + [id])
		return
	if _held or _scope.is_empty() or not _same_configuration(configuration):
		_fail.call_deferred(id, operation)
		return
	if _mutation_pending():
		if _waiting_reads.size() >= MAX_READERS: _fail.call_deferred(id, operation)
		else: _waiting_reads.append({"id":id, "operation":operation, "arguments":arguments.duplicate(true), "configuration":configuration.duplicate(true), "force":force, "identity_generation":identity_generation, "generation":generation, "deadline":Time.get_ticks_msec() + READ_TIMEOUT_MS})
		_refresh_processing()
		return
	if operation == "configure" and (arguments.size() != 3 or arguments[0] != _configuration.get("revenuecat_public_key") or arguments[1] != _owner or arguments[2] != _configuration.get("purchase_mode")):
		_fail.call_deferred(id, operation)
		return
	if operation == "get_customer_info" and not _configured and (_read.is_empty() or _read.operation != "configure"):
		_fail.call_deferred(id, operation)
		return
	if force: invalidate()
	if _configured and not _cache.is_empty():
		_deliver.call_deferred(id, operation, _cache.duplicate(true), _generation, _revision)
		return
	if not _read.is_empty():
		if _read.waiters.size() >= MAX_READERS:
			_fail.call_deferred(id, operation)
		else:
			_read.waiters.append({"id": id, "operation": operation})
		return
	_read = {"id": id, "operation": operation, "generation": _generation, "revision": _revision,
		"deadline": Time.get_ticks_msec() + READ_TIMEOUT_MS, "waiters": [{"id": id, "operation": operation}]}
	set_process(true)
	_native.callv(operation, arguments + [id])

func _same_configuration(configuration: Dictionary) -> bool:
	for key: String in ["purchase_mode", "entitlement_id", "revenuecat_public_key"]:
		if configuration.get(key) != _configuration.get(key): return false
	return str(configuration.get("api_base_url", "")).trim_suffix("/") == str(_configuration.get("api_base_url", "")).trim_suffix("/")

func _valid(payload: Variant) -> bool:
	if not payload is Dictionary or payload.get("schema_version") != 1 or payload.get("mode") != "google_play" or payload.get("player_id") != _owner or not payload.get("entitlements") is Dictionary: return false
	if not (payload.get("request_date_ms") is int or payload.get("request_date_ms") is float) or not is_finite(float(payload.request_date_ms)) or float(payload.request_date_ms) < 0: return false
	for entry: Variant in payload.entitlements.values():
		if not entry is Dictionary or not entry.get("active") is bool or not entry.get("store") is String or not entry.get("product_id") is String: return false
	return true

func _result(id: String, operation: String, json: String) -> void:
	if _writes.has(id):
		var write: Dictionary = _writes[id]
		_writes.erase(id)
		_refresh_processing()
		if write.operation != operation or write.generation != _identity_generation or _held: return
		if operation in ["purchase_package", "restore_purchases"]:
			var result: Variant = JSON.parse_string(json)
			if not _valid(result):
				_fail(id, operation)
				_drain_reads()
				return
			result = _newest(result)
			_cache = result.duplicate(true)
			_latest = _cache.duplicate(true)
			_revision += 1
			json = JSON.stringify(result)
		request_result.emit(id, operation, json)
		_drain_reads()
		return
	if _read.is_empty() or _read.id != id or _read.operation != operation: return
	var read: Dictionary = _read
	_read = {}
	_refresh_processing()
	if read.generation != _generation or _held: return
	var payload: Variant = JSON.parse_string(json)
	if not _valid(payload):
		for waiter: Dictionary in read.waiters: _fail(waiter.id, waiter.operation)
		return
	payload = _newest(payload)
	_configured = true
	_cache = payload.duplicate(true)
	_latest = _cache.duplicate(true)
	_revision += 1
	for waiter: Dictionary in read.waiters:
		_deliver.call_deferred(waiter.id, waiter.operation, payload.duplicate(true), _generation, _revision)

func _error(id: String, operation: String, code: String, message: String, cancelled: bool) -> void:
	if _writes.has(id):
		var write: Dictionary = _writes[id]
		_writes.erase(id)
		_refresh_processing()
		if write.operation == operation and write.generation == _identity_generation and not _held:
			request_error.emit(id, operation, code, message, cancelled)
		_drain_reads()
		return
	if _read.is_empty() or _read.id != id or _read.operation != operation: return
	var waiters: Array = _read.waiters
	_read = {}
	_refresh_processing()
	for waiter: Dictionary in waiters:
		request_error.emit(waiter.id, waiter.operation, code, message, cancelled)

func _updated(json: String) -> void:
	var payload: Variant = JSON.parse_string(json)
	if not _valid(payload): return
	if not _latest.is_empty() and float(payload.request_date_ms) < float(_latest.request_date_ms): return
	if payload != _latest: ReviewAccess.forget_shared()
	if _held:
		# A secure identity reread holds authority, not relevant revocations.
		# Require fresh confirmation after a changed SDK event during that hold.
		if payload != _latest:
			_cache.clear()
			_latest = payload.duplicate(true)
			_revision += 1
		return
	json = JSON.stringify(payload)
	if payload != _cache:
		_cache = payload.duplicate(true)
		_latest = _cache.duplicate(true)
		_revision += 1
	customer_info_updated.emit(json)

func _deliver(id: String, operation: String, payload: Dictionary, generation: int, revision: int) -> void:
	if _held or generation != _generation:
		_fail(id, operation)
		return
	if revision != _revision:
		if _cache.is_empty():
			_fail(id, operation)
			return
		payload = _cache.duplicate(true)
	request_result.emit(id, operation, JSON.stringify(payload))

func _fail(id: String, operation: String) -> void:
	request_error.emit(id, operation, "purchase_session_changed", PlayerCopy.PURCHASES_1A3E50F05727, false)

func _cancel_read() -> void:
	if _read.is_empty(): return
	var waiters: Array = _read.waiters
	_read = {}
	_refresh_processing()
	for waiter: Dictionary in waiters: _fail.call_deferred(waiter.id, waiter.operation)

func _process(_delta: float) -> void:
	if not _read.is_empty() and Time.get_ticks_msec() >= _read.deadline: _cancel_read()
	for index in range(_waiting_reads.size() - 1, -1, -1):
		var reader: Dictionary = _waiting_reads[index]
		if Time.get_ticks_msec() >= reader.deadline:
			_waiting_reads.remove_at(index)
			_fail(reader.id, reader.operation)
	for id: String in _writes.keys():
		if Time.get_ticks_msec() >= _writes[id].deadline:
			var operation: String = _writes[id].operation
			_writes.erase(id)
			_fail(id, operation)
	_drain_reads()
	_refresh_processing()

func _refresh_processing() -> void:
	set_process(not _read.is_empty() or not _waiting_reads.is_empty() or not _writes.is_empty())

func _mutation_pending() -> bool:
	for write: Dictionary in _writes.values():
		if write.operation in ["purchase_package", "restore_purchases"]: return true
	return false

func _drain_reads() -> void:
	if _mutation_pending() or _waiting_reads.is_empty(): return
	var readers: Array[Dictionary] = _waiting_reads
	_waiting_reads = []
	_refresh_processing()
	var force := false
	for reader: Dictionary in readers: force = force or reader.force
	for reader: Dictionary in readers:
		dispatch(reader.id, reader.operation, reader.arguments, reader.configuration, force, reader.identity_generation, reader.generation)
		force = false

func _newest(payload: Dictionary) -> Dictionary:
	if not _latest.is_empty() and float(_latest.request_date_ms) > float(payload.request_date_ms): return _latest.duplicate(true)
	return payload

func current_generation() -> int:
	return _generation

func identity_generation() -> int:
	return _identity_generation

func accepts(configuration: Dictionary, generation: int, identity: int) -> bool:
	return not _held and _configured and generation == _generation and identity == _identity_generation and _same_configuration(configuration)

static func _id(value: String, minimum: int, maximum: int) -> bool:
	return value.length() >= minimum and value.length() <= maximum and RegEx.create_from_string("^[A-Za-z0-9_-]+$").search(value) != null
