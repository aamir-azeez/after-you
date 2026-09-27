extends SceneTree

const Access = preload("res://services/chapter_access.gd")
const Purchases = preload("res://services/purchases.gd")
var checks := 0
var failures := 0

class Store extends Purchases:
	var requests: Array[String] = []
	func _connect_native() -> bool: return true
	func refresh_customer_info() -> String:
		var id := "access-%d" % requests.size()
		requests.append(id)
		return id
	func answer(id: String, active: bool) -> void:
		customer_info = {"schema_version": 1, "entitlements": {"full_journey": {"active": active}}}
		customer_info_changed.emit(customer_info)
		completed.emit(id, "get_customer_info", customer_info)
	func revoke() -> void:
		customer_info_changed.emit({"schema_version": 1, "entitlements": {}})

class Tester extends Node:
	signal released
	var delayed := false
	var calls := 0
	var invalidations := 0
	var result := {"ok": true, "granted": false, "durable": true}
	func load_cached(_url: String) -> Dictionary:
		calls += 1
		if delayed: await released
		return result.duplicate(true)
	func invalidate() -> void: invalidations += 1

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	await _purchase_lifecycle()
	await _tester_lifecycle()
	await _direct_desktop_fails_closed()
	print("CHAPTER ACCESS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _purchase_lifecycle() -> void:
	var store := Store.new()
	store._configuration = {"purchase_mode": "test_store", "entitlement_id": "full_journey"}
	var gate := Access.new()
	gate.purchase_service_factory = func(): return store
	root.add_child(gate)
	_check(not gate.is_granted(), "Premium admission starts closed before any journal is eligible to load")
	gate.check_access()
	_check(gate.state == "checking" and store.requests.size() == 1, "Admission asks for fresh provider information")
	gate.check_access()
	_check(store.requests.size() == 1, "Repeated scene checks coalesce while the request is pending")
	store.customer_info_changed.emit({"schema_version": 1, "entitlements": {"full_journey": {"active": true}}})
	_check(not gate.is_granted(), "Unsolicited active customer information never grants access")
	store.answer("unowned", true)
	_check(not gate.is_granted(), "Another request's completion cannot grant access")
	store.answer(store.requests[-1], false)
	_check(gate.state == "hold" and gate.reason == "purchase_required", "A nonbuyer remains held")
	gate.check_access()
	var expired: String = store.requests[-1]
	gate._deadline = Time.get_ticks_msec() - 1
	gate._process(0.0)
	_check(gate.state == "hold" and gate.reason == "timeout", "A lost provider callback has a bounded hold")
	store.answer(expired, true)
	_check(not gate.is_granted(), "Timed-out success cannot grant access later")
	gate.check_access()
	store.answer(store.requests[-1], true)
	_check(gate.is_granted() and gate.reason == "purchase", "Only the exact successful provider request admits a buyer")
	store.revoke()
	_check(not gate.is_granted() and gate.reason == "purchase_revoked", "Explicit entitlement loss immediately suspends admission")
	gate.check_access()
	var stale: String = store.requests[-1]
	gate.set_backgrounded(true)
	store.answer(stale, true)
	_check(not gate.is_granted() and gate.reason == "backgrounded", "A backgrounded scene ignores its former completion")
	gate.set_backgrounded(false)
	var count := store.requests.size()
	gate.set_backgrounded(false)
	_check(store.requests.size() == count and gate.state == "checking", "Foreground and paired focus events perform one fresh check")
	store.answer(stale, true)
	_check(not gate.is_granted(), "An earlier foreground generation cannot satisfy the current check")
	store.answer(store.requests[-1], true)
	_check(gate.is_granted(), "The current foreground result restores admission without controlling gameplay")
	gate.check_access()
	var review: String = store.requests[-1]
	store.review_verification_started.emit(review)
	_check(gate._deadline - Time.get_ticks_msec() > 29000, "Authenticated review verification receives the bounded extended deadline")
	store.failed.emit(review, "get_customer_info", "unavailable", "", false)
	_check(gate.state == "hold" and gate.reason == "provider_unavailable", "Provider failure remains closed and retryable")
	gate.check_access()
	var leaving: String = store.requests[-1]
	gate.close()
	store.answer(leaving, true)
	_check(not gate.is_granted() and gate.reason == "closed", "Closing invalidates late success before scene destruction")
	gate.queue_free()
	await process_frame

func _tester_lifecycle() -> void:
	var store := Store.new()
	store._configuration = {"purchase_mode": "test_store", "entitlement_id": "full_journey"}
	var tester := Tester.new()
	tester.result = {"ok": true, "granted": true, "durable": true}
	var gate := Access.new()
	gate.purchase_service_factory = func(): return store
	gate.tester_access_factory = func(): return tester
	gate.api_base_url = "https://example.invalid"
	root.add_child(gate)
	gate.check_access()
	_check(gate.is_granted() and gate.reason == "tester" and store.requests.is_empty(), "Durable cached tester access admits without creating a store request")
	gate.set_backgrounded(true)
	tester.delayed = true
	gate.set_backgrounded(false)
	_check(not gate.is_granted() and tester.calls == 2, "Foreground revalidates the cached tester binding before admission")
	gate.set_backgrounded(true)
	tester.released.emit()
	_check(not gate.is_granted() and gate.reason == "backgrounded", "Stale asynchronous tester success cannot unlock a backgrounded scene")
	tester.delayed = false
	tester.result.durable = false
	gate.set_backgrounded(false)
	_check(not gate.is_granted() and store.requests.size() == 1, "An unpersisted tester grant cannot bypass fresh provider admission")
	store.answer(store.requests[-1], true)
	_check(gate.is_granted() and gate.reason == "purchase", "A buyer can recover after an unusable local tester receipt")
	gate.set_backgrounded(true)
	tester.delayed = true
	gate.set_backgrounded(false)
	gate._deadline = Time.get_ticks_msec() - 1
	gate._process(0.0)
	tester.result.durable = true
	tester.released.emit()
	_check(not gate.is_granted() and gate.reason == "timeout", "A timed-out tester response also fails closed")
	gate.queue_free()
	await process_frame

func _direct_desktop_fails_closed() -> void:
	var gate := Access.new()
	root.add_child(gate)
	gate.check_access()
	await process_frame
	_check(not gate.is_granted() and gate.state == "hold", "Using the admission service without a configured Android provider never invents an entitlement")
	gate.queue_free()
	await process_frame

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
