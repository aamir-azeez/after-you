class_name PurchaseService
extends Node
const PlayerCopy = preload("res://presentation/player_copy.gd")
## Android RevenueCat facade. Desktop builds report unavailable; they never simulate a purchase.

signal completed(request_id: String, operation: String, payload: Dictionary)
signal failed(request_id: String, operation: String, code: String, message: String, cancelled: bool)
signal customer_info_changed(payload: Dictionary)
signal review_verification_started(request_id: String)

const ReviewAccess = preload("res://services/review_access.gd")
const PurchaseSession = preload("res://services/purchase_session.gd")
const PLAY_PRODUCT := "after_you_full_journey"

var customer_info: Dictionary = {}
var offerings: Dictionary = {}
var _native: Object
var native_factory: Callable
var _session: Node
var _session_generation := -1
var _session_identity_generation := -1
var _pending: Dictionary = {}
var _configuration: Dictionary = read_configuration()
var review_access_factory: Callable
var _review_access: Node
var _review_payload: Dictionary = {}
var _review_generation := 0
var _backgrounded := false

static func read_configuration() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://app_config.json"))
	return parsed if parsed is Dictionary else {}

func _ready() -> void:
	_connect_native()

static func store_enabled(configuration: Dictionary) -> bool:
	return configuration.get("purchase_mode") == "google_play" and configuration.get("entitlement_id") == "full_journey_play"

func _connect_native() -> bool:
	if not store_enabled(_configuration): return false
	if is_instance_valid(_session): return true
	if _native == null:
		if native_factory.is_valid(): _native = native_factory.call()
		elif Engine.has_singleton("AfterYouAndroid"): _native = Engine.get_singleton("AfterYouAndroid")
		else: return false
	_session = PurchaseSession.shared(get_tree(), _native)
	_session_identity_generation = _session.identity_generation()
	_session.request_result.connect(_on_result)
	_session.request_error.connect(_on_error)
	_session.customer_info_updated.connect(_on_customer_info)
	return true

func bind_session(owner: String, token: String) -> void:
	if _connect_native() and is_instance_valid(_session):
		_session.bind_context(_configuration, owner, token)
		_session_identity_generation = _session.identity_generation()

static func suspend_session(clear: bool) -> void:
	PurchaseSession.suspend_shared(clear)
	if clear: ReviewAccess.forget_shared()

func invalidate_session_reads() -> void:
	if is_instance_valid(_session): _session.invalidate()
	ReviewAccess.forget_shared()

func is_available() -> bool:
	return store_enabled(_configuration) and _connect_native()

func configure_store(public_key: String, player_id: String, mode: String) -> String:
	return _request("configure", [public_key, player_id, mode])

func fetch_offerings() -> String:
	return _request("get_offerings", [])

func refresh_customer_info() -> String:
	return _request("get_customer_info", [])

func refresh_customer_info_fresh() -> String:
	ReviewAccess.forget_shared()
	return _request("get_customer_info", [], true)

func purchase(offering_id: String, package_id: String) -> String:
	return _request("purchase_package", [offering_id, package_id])

func restore() -> String:
	return _request("restore_purchases", [])

func has_entitlement(entitlement_id: String = "") -> bool:
	if is_instance_valid(_session) and not _session.accepts(_configuration, _session_generation, _session_identity_generation): return false
	if not entitlement_id.is_empty() and entitlement_id != _configuration.get("entitlement_id", ""):
		return false
	return entitled_payload(customer_info)

func entitled_payload(payload: Dictionary) -> bool:
	if is_instance_valid(_session) and not _session.accepts(_configuration, _session_generation, _session_identity_generation): return false
	return entitled_for_configuration(payload, _configuration) or (not _backgrounded and not _review_payload.is_empty() and payload == _review_payload and review_candidate(payload, _configuration))

func needs_review_verification() -> bool:
	return review_candidate(customer_info, _configuration)

func invalidate_review_access() -> void:
	_review_generation += 1
	_review_payload.clear()
	# The shared verifier may be serving another scene. Local generations already
	# reject this caller's late reply; scene destruction must not cancel peers.
	if is_instance_valid(_review_access) and not _review_access is ReviewAccess: _review_access.invalidate()

static func review_candidate(payload: Dictionary, configuration: Dictionary) -> bool:
	if configuration.get("purchase_mode") != "google_play" or configuration.get("entitlement_id") != "full_journey_play" or payload.get("schema_version") != 1 or payload.get("mode") != "google_play": return false
	var entries: Variant = payload.get("entitlements")
	if not entries is Dictionary: return false
	var entry: Variant = entries.get("full_journey_play")
	return entry is Dictionary and entry.get("active") is bool and entry.active and entry.get("store") == "PROMOTIONAL"

static func entitled_for_configuration(payload: Dictionary, configuration: Dictionary) -> bool:
	if not store_enabled(configuration): return false
	var entries: Variant = payload.get("entitlements", {})
	if not entries is Dictionary: return false
	var entry: Variant = entries.get("full_journey_play", {})
	if not entry is Dictionary or not entry.get("active") is bool or not entry.active: return false
	# Promotional reviewer access requires its separate authenticated check.
	# A Test Store receipt never unlocks a distributed build, including debug APKs.
	return payload.get("schema_version") == 1 and payload.get("mode") == "google_play" and entry.get("store") == "PLAY_STORE" and entry.get("product_id") == PLAY_PRODUCT

static func select_lifetime_offer(payload: Dictionary) -> Dictionary:
	# Read the native formatter's real schema. Never relabel a subscription as
	# the promised one-time purchase or silently choose a noncurrent offering.
	var current_id: String=str(payload.get("current_id",""))
	for entry: Variant in payload.get("offerings",[]):
		if not entry is Dictionary or str(entry.get("id",""))!=current_id:
			continue
		for item: Variant in entry.get("packages",[]):
			if item is Dictionary and item.get("type","")=="LIFETIME" and not str(item.get("price","")).is_empty() and not str(item.get("id","")).is_empty():
				var selected: Dictionary=item.duplicate(true)
				selected["offering_id"]=current_id
				return selected
	return {}

func _request(operation: String, arguments: Array, force: bool = false) -> String:
	if operation != "get_offerings": invalidate_review_access()
	if operation in ["purchase_package", "restore_purchases"]: ReviewAccess.forget_shared()
	var id := Crypto.new().generate_random_bytes(16).hex_encode()
	_pending[id] = operation
	if not store_enabled(_configuration):
		_store_disabled.call_deferred(id, operation)
		return id
	if not _connect_native():
		_unavailable.call_deferred(id, operation)
		return id
	_session.dispatch(id, operation, arguments, _configuration, force, _session_identity_generation, _session_generation)
	return id

func _store_disabled(id: String, operation: String) -> void:
	_on_error(id, operation, "store_disabled", "Google Play", false)

func _unavailable(id: String, operation: String) -> void:
	_on_error(id, operation, "android_required", PlayerCopy.PURCHASES_49387E2DE82E, false)

func _on_result(id: String, operation: String, payload_json: String) -> void:
	if not store_enabled(_configuration):
		_store_disabled(id, operation)
		return
	if _pending.get(id, "") != operation:
		return
	var parsed: Variant = JSON.parse_string(payload_json)
	if not parsed is Dictionary or parsed.get("schema_version", 0) != 1:
		_on_error(id, operation, "invalid_native_response", PlayerCopy.PURCHASES_79A34D6B63D8, false)
		return
	_pending.erase(id)
	var session_generation: int = _session.current_generation() if is_instance_valid(_session) else -1
	if operation == "get_offerings":
		offerings = parsed
	else:
		customer_info = parsed
		_review_payload.clear()
		if review_candidate(parsed, _configuration):
			var generation := _review_generation
			review_verification_started.emit(id)
			if not is_instance_valid(_review_access):
				if review_access_factory.is_valid():
					_review_access = review_access_factory.call()
					add_child(_review_access)
				else: _review_access = ReviewAccess.shared(get_tree())
			var authorized: bool = await _review_access.verify(str(parsed.get("player_id", "")), str(_configuration.get("api_base_url", "")))
			if not is_inside_tree() or generation != _review_generation or customer_info != parsed or _backgrounded or (is_instance_valid(_session) and not _session.accepts(_configuration, session_generation, _session_identity_generation)):
				failed.emit(id, operation, "review_access_changed", PlayerCopy.PURCHASES_1A3E50F05727, false)
				return
			if authorized: _review_payload = parsed.duplicate(true)
		_session_generation = session_generation
		customer_info_changed.emit(customer_info)
	completed.emit(id, operation, parsed)

func _on_error(id: String, operation: String, code: String, message: String, cancelled: bool) -> void:
	if _pending.get(id, "") != operation:
		return
	_pending.erase(id)
	failed.emit(id, operation, code, message, cancelled)

func _on_customer_info(payload_json: String) -> void:
	if not store_enabled(_configuration): return
	if is_instance_valid(_session) and _session.identity_generation() != _session_identity_generation: return
	var parsed: Variant = JSON.parse_string(payload_json)
	if parsed is Dictionary and parsed.get("schema_version", 0) == 1:
		if parsed != customer_info:
			invalidate_review_access()
			ReviewAccess.forget_shared()
		customer_info = parsed
		if is_instance_valid(_session): _session_generation = _session.current_generation()
		customer_info_changed.emit(customer_info)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		_backgrounded = true
		invalidate_review_access()
		ReviewAccess.forget_shared()
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		_backgrounded = false

func _exit_tree() -> void:
	invalidate_review_access()
