class_name PurchaseService
extends Node
## Android RevenueCat facade. Desktop builds report unavailable; they never simulate a purchase.

signal completed(request_id: String, operation: String, payload: Dictionary)
signal failed(request_id: String, operation: String, code: String, message: String, cancelled: bool)
signal customer_info_changed(payload: Dictionary)

var customer_info: Dictionary = {}
var offerings: Dictionary = {}
var _native: Object
var _pending: Dictionary = {}
var _configuration: Dictionary = read_configuration()

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
	return entitled_for_configuration(customer_info, _configuration)

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
	# A RevenueCat project can contain multiple stores. A demo entitlement or
	# promotional grant must never unlock the Google Play application.
	if mode == "google_play":
		return payload.get("schema_version") == 1 and payload.get("mode") == mode and entry.get("store") == "PLAY_STORE"
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
	var id := Crypto.new().generate_random_bytes(16).hex_encode()
	_pending[id] = operation
	if not _connect_native():
		_unavailable.call_deferred(id, operation)
		return id
	arguments.append(id)
	_native.callv(operation, arguments)
	return id

func _unavailable(id: String, operation: String) -> void:
	_on_error(id, operation, "android_required", "Purchases require an Android build with the store configured.", false)

func _on_result(id: String, operation: String, payload_json: String) -> void:
	if _pending.get(id, "") != operation:
		return
	var parsed: Variant = JSON.parse_string(payload_json)
	if not parsed is Dictionary or parsed.get("schema_version", 0) != 1:
		_on_error(id, operation, "invalid_native_response", "The store response was not understood.", false)
		return
	_pending.erase(id)
	if operation == "get_offerings":
		offerings = parsed
	else:
		customer_info = parsed
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
		customer_info = parsed
		customer_info_changed.emit(customer_info)
