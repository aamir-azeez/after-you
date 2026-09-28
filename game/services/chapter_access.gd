extends Node
## Admission for premium solo chapters. This service never touches a journey.
## The scene owns pausing/saving before presenting an access state change.

signal state_changed(state: String, reason: String)

const Purchases = preload("res://services/purchases.gd")
const TesterAccess = preload("res://services/tester_access.gd")

var purchase_service_factory: Callable
var tester_access_factory: Callable
var state := "hold"
var reason := "not_checked"
var api_base_url := ""
var _purchases: Node
var _tester: Node
var _generation := 0
var _request := ""
var _deadline := 0
var _tester_checking := false
var _tester_admitted := false
var _backgrounded := false
var _closed := false
var _force_refresh := false

func _ready() -> void:
	if api_base_url.is_empty():
		api_base_url = str(Purchases.read_configuration().get("api_base_url", ""))

func is_granted() -> bool:
	return state == "granted" and not _closed and not _backgrounded

func check_access(force_refresh: bool = false) -> void:
	if _closed or _backgrounded or not is_inside_tree() or state == "checking": return
	_force_refresh = force_refresh
	_generation += 1
	_tester_admitted = false
	_set_state("checking", "checking")
	if OS.get_name() == "Android" or tester_access_factory.is_valid():
		_check_tester(_generation)
	else:
		_check_purchase()

func _check_tester(generation: int) -> void:
	if not is_instance_valid(_tester):
		_tester = tester_access_factory.call() if tester_access_factory.is_valid() else TesterAccess.new()
		add_child(_tester)
	_tester_checking = true
	_deadline = Time.get_ticks_msec() + 60000
	var result: Dictionary = await _tester.load_cached(api_base_url)
	if not _current(generation): return
	_tester_checking = false
	if result.get("ok") == true and result.get("granted") == true and result.get("durable") == true:
		_tester_admitted = true
		_deadline = 0
		_set_state("granted", "tester")
	else:
		_check_purchase()

func _check_purchase() -> void:
	if _closed or _backgrounded: return
	if not is_instance_valid(_purchases):
		_purchases = purchase_service_factory.call() if purchase_service_factory.is_valid() else Purchases.new()
		add_child(_purchases)
		_purchases.completed.connect(_completed)
		_purchases.failed.connect(_failed)
		_purchases.customer_info_changed.connect(_changed)
		_purchases.review_verification_started.connect(_review_started)
	_deadline = Time.get_ticks_msec() + (30000 if _purchases.needs_review_verification() else 10000)
	# Only the shared, identity-bound provider session can satisfy a cached read.
	_request = _purchases.refresh_customer_info_fresh() if _force_refresh else _purchases.refresh_customer_info()
	if _request.is_empty():
		_deadline = 0
		_set_state("hold", "provider_unavailable")

func _completed(id: String, operation: String, payload: Dictionary) -> void:
	if not _matches(id, operation): return
	_request = ""
	_deadline = 0
	_set_state("granted" if _entitled(payload) else "hold", "purchase" if _entitled(payload) else "purchase_required")

func _failed(id: String, operation: String, _code: String, _message: String, _cancelled: bool) -> void:
	if not _matches(id, operation): return
	_request = ""
	_deadline = 0
	_purchases.invalidate_review_access()
	_set_state("hold", "provider_unavailable")

func _changed(payload: Dictionary) -> void:
	# Only a matching completion can grant access. Explicit revocation can
	# suspend an admitted buyer, but does not revoke an independent tester grant.
	if _closed or _backgrounded or _tester_admitted or not _request.is_empty() or not is_granted(): return
	if not _entitled(payload):
		_purchases.invalidate_review_access()
		_set_state("hold", "purchase_revoked")

func _review_started(id: String) -> void:
	if not _closed and not _backgrounded and not id.is_empty() and id == _request:
		_deadline = Time.get_ticks_msec() + 30000

func _entitled(payload: Dictionary) -> bool:
	return payload.get("schema_version") == 1 and is_instance_valid(_purchases) and _purchases.entitled_payload(payload)

func _matches(id: String, operation: String) -> bool:
	return not _closed and not _backgrounded and not _tester_admitted and not id.is_empty() and id == _request and operation == "get_customer_info"

func _current(generation: int) -> bool:
	return generation == _generation and not _closed and not _backgrounded and is_inside_tree()

func _process(_delta: float) -> void:
	if _closed or _backgrounded or state != "checking" or _deadline == 0 or Time.get_ticks_msec() < _deadline: return
	_cancel_pending()
	_set_state("hold", "timeout")

func set_backgrounded(value: bool) -> void:
	if _closed or value == _backgrounded: return
	_backgrounded = value
	_cancel_pending()
	_set_state("hold", "backgrounded" if value else "not_checked")
	if not value: check_access()

func close() -> void:
	if _closed: return
	_closed = true
	_cancel_pending()
	_set_state("hold", "closed")

func _cancel_pending() -> void:
	_generation += 1
	_request = ""
	_deadline = 0
	_tester_checking = false
	_tester_admitted = false
	if is_instance_valid(_tester): _tester.invalidate()
	if is_instance_valid(_purchases): _purchases.invalidate_review_access()

func _set_state(next: String, detail: String) -> void:
	if state == next and reason == detail: return
	state = next
	reason = detail
	state_changed.emit(state, reason)

func _exit_tree() -> void:
	close()
