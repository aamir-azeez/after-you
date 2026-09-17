class_name PurchaseService
extends Node
const PlayerCopy = preload("res://presentation/player_copy.gd")
## Android RevenueCat facade. Desktop builds report unavailable; they never simulate a purchase.

signal completed(request_id: String, operation: String, payload: Dictionary)
signal failed(request_id: String, operation: String, code: String, message: String, cancelled: bool)
signal customer_info_changed(payload: Dictionary)
signal review_verification_started(request_id: String)

const ReviewAccess = preload("res://services/review_access.gd")
const PLAY_PRODUCT := "after_you_full_journey"

var customer_info: Dictionary = {}
var offerings: Dictionary = {}
var _native: Object
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

func _connect_native() -> bool:
	if _native != null:
		return true
	if not Engine.has_singleton("AfterYouAndroid"):
		return false
	_native = Engine.get_singleton("AfterYouAndroid")
	_native.connect("request_result", _on_result)
	_native.connect("request_error", _on_error)
	_native.connect("customer_info_updated", _on_customer_info)
	return true

func is_available() -> bool:
	return _connect_native()

func configure_store(public_key: String, player_id: String, mode: String) -> String:
	return _request("configure", [public_key, player_id, mode])

func fetch_offerings() -> String:
	return _request("get_offerings", [])

func refresh_customer_info() -> String:
	return _request("get_customer_info", [])

func purchase(offering_id: String, package_id: String) -> String:
	return _request("purchase_package", [offering_id, package_id])

func restore() -> String:
	return _request("restore_purchases", [])

func has_entitlement(entitlement_id: String = "") -> bool:
	if not entitlement_id.is_empty() and entitlement_id != _configuration.get("entitlement_id", ""):
		return false
	return entitled_payload(customer_info)

func entitled_payload(payload: Dictionary) -> bool:
	return entitled_for_configuration(payload, _configuration) or (not _backgrounded and not _review_payload.is_empty() and payload == _review_payload and review_candidate(payload, _configuration))

func needs_review_verification() -> bool:
	return review_candidate(customer_info, _configuration)

func invalidate_review_access() -> void:
	_review_generation += 1
	_review_payload.clear()
	if is_instance_valid(_review_access): _review_access.invalidate()

static func review_candidate(payload: Dictionary, configuration: Dictionary) -> bool:
	if configuration.get("purchase_mode") != "google_play" or configuration.get("entitlement_id") != "full_journey_play" or payload.get("schema_version") != 1 or payload.get("mode") != "google_play": return false
	var entries: Variant = payload.get("entitlements")
	if not entries is Dictionary: return false
	var entry: Variant = entries.get("full_journey_play")
	return entry is Dictionary and entry.get("active") is bool and entry.active and entry.get("store") == "PROMOTIONAL"

static func entitled_for_configuration(payload: Dictionary, configuration: Dictionary) -> bool:
	var mode: String = str(configuration.get("purchase_mode", ""))
	var entitlement: String = str(configuration.get("entitlement_id", ""))
	if (mode == "test_store" and entitlement != "full_journey") or (mode == "google_play" and entitlement != "full_journey_play"):
		return false
	if mode not in ["test_store", "google_play"]: return false
	var entries: Variant = payload.get("entitlements", {})
	if not entries is Dictionary: return false
	var entry: Variant = entries.get(entitlement, {})
	if not entry is Dictionary or not entry.get("active") is bool or not entry.active: return false
	# A RevenueCat project can contain multiple stores. Promotional review access
	# is checked separately against the authenticated service, never here.
	if mode == "google_play":
		return payload.get("schema_version") == 1 and payload.get("mode") == mode and entry.get("store") == "PLAY_STORE" and entry.get("product_id") == PLAY_PRODUCT
	return true

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

func _request(operation: String, arguments: Array) -> String:
	if operation != "get_offerings": invalidate_review_access()
	var id := Crypto.new().generate_random_bytes(16).hex_encode()
	_pending[id] = operation
	if not _connect_native():
		_unavailable.call_deferred(id, operation)
		return id
	arguments.append(id)
	_native.callv(operation, arguments)
	return id

func _unavailable(id: String, operation: String) -> void:
	_on_error(id, operation, "android_required", PlayerCopy.PURCHASES_49387E2DE82E, false)

func _on_result(id: String, operation: String, payload_json: String) -> void:
	if _pending.get(id, "") != operation:
		return
	var parsed: Variant = JSON.parse_string(payload_json)
	if not parsed is Dictionary or parsed.get("schema_version", 0) != 1:
		_on_error(id, operation, "invalid_native_response", PlayerCopy.PURCHASES_79A34D6B63D8, false)
		return
	_pending.erase(id)
	if operation == "get_offerings":
		offerings = parsed
	else:
		customer_info = parsed
		_review_payload.clear()
		if review_candidate(parsed, _configuration):
			var generation := _review_generation
			review_verification_started.emit(id)
			if not is_instance_valid(_review_access):
				_review_access = review_access_factory.call() if review_access_factory.is_valid() else ReviewAccess.new()
				add_child(_review_access)
			var authorized: bool = await _review_access.verify(str(parsed.get("player_id", "")), str(_configuration.get("api_base_url", "")))
			if not is_inside_tree() or generation != _review_generation or customer_info != parsed or _backgrounded:
				failed.emit(id, operation, "review_access_changed", PlayerCopy.PURCHASES_1A3E50F05727, false)
				return
			if authorized: _review_payload = parsed.duplicate(true)
		customer_info_changed.emit(customer_info)
	completed.emit(id, operation, parsed)

func _on_error(id: String, operation: String, code: String, message: String, cancelled: bool) -> void:
	if _pending.get(id, "") != operation:
		return
	_pending.erase(id)
	failed.emit(id, operation, code, message, cancelled)

func _on_customer_info(payload_json: String) -> void:
	var parsed: Variant = JSON.parse_string(payload_json)
	if parsed is Dictionary and parsed.get("schema_version", 0) == 1:
		if parsed != customer_info: invalidate_review_access()
		customer_info = parsed
		customer_info_changed.emit(customer_info)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		_backgrounded = true
		invalidate_review_access()
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		_backgrounded = false

func _exit_tree() -> void:
	invalidate_review_access()
