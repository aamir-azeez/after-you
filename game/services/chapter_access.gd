extends Node
## Admission for premium solo chapters. This service never touches a journey.
## The scene owns pausing/saving before presenting an access state change.

signal state_changed(state: String, reason: String)

const Purchases = preload("res://services/purchases.gd")
const TesterAccess = preload("res://services/tester_access.gd")
const PlatformSupport = preload("res://services/platform_support.gd")

var purchase_service_factory: Callable
var tester_access_factory: Callable
## The scene this admission is for. Its first check takes Main's tester check
## for that scene, when Main handed one over (hand_over).
var opened_scene := ""
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
## Main's read of the saved tester receipt, for the paid scene it is opening.
static var _handed: Dictionary = {}

## Main hands over its tester check in the frame it opens `scene`: `granted`
## says whether its read of the saved receipt, for the identity now in use at
## `base_url`, found a tester grant. That scene's first check uses it instead of
## reading the receipt again; any later check (Check again, a return from the
## background) reads it again. It lasts only for that scene change: the next
## frame at most.
static func hand_over(scene: String, base_url: String, granted: bool) -> void:
	_handed = {"scene": scene, "authority": TesterAccess._authority(base_url), "granted": granted, "frame": Engine.get_process_frames()}

static func drop_hand_over() -> void:
	_handed = {}

## The hand-off for `scene` at `base_url`, once; empty when there is none. Taking
## it removes it, whichever scene it was for.
static func _take_hand_over(scene: String, base_url: String) -> Dictionary:
	var handed := _handed
	_handed = {}
	var authority := TesterAccess._authority(base_url)
	if handed.is_empty() or Engine.get_process_frames() - int(handed.frame) > 1: return {}
	if handed.scene != scene or authority.is_empty() or handed.authority != authority: return {}
	return handed

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
	if not PlatformSupport.store_gated() and not tester_access_factory.is_valid():
		_check_purchase()
		return
	var handed := {} if opened_scene.is_empty() else _take_hand_over(opened_scene, api_base_url)
	opened_scene = ""
	if handed.is_empty(): _check_tester(_generation)
	elif handed.granted: _admit_tester()
	else: _check_purchase()

func _check_tester(generation: int) -> void:
	if not is_instance_valid(_tester):
		_tester = tester_access_factory.call() if tester_access_factory.is_valid() else TesterAccess.new()
		add_child(_tester)
	_tester_checking = true
	_deadline = Time.get_ticks_msec() + 60000
	var result: Dictionary = await _tester.load_cached(api_base_url)
	if not _current(generation): return
	_tester_checking = false
	if result.get("ok") == true and result.get("granted") == true and result.get("durable") == true: _admit_tester()
	else: _check_purchase()

func _admit_tester() -> void:
	_tester_admitted = true
	_deadline = 0
	_set_state("granted", "tester")

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
