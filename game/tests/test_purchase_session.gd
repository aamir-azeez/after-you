extends SceneTree

const Purchases = preload("res://services/purchases.gd")
const Session = preload("res://services/purchase_session.gd")
const Access = preload("res://services/chapter_access.gd")
const Review = preload("res://services/review_access.gd")
const Main = preload("res://main.gd")
const Storage = preload("res://services/local_save.gd")
const Lighthouse = preload("res://lighthouse_preview.gd")
const OWNER := "PPPPPPPPPPPPPPPPPPPPPP"
const TOKEN := "DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD"
const CONFIG := {"purchase_mode":"google_play", "entitlement_id":"full_journey_play", "revenuecat_public_key":"goog_session_test", "api_base_url":"https://example.invalid"}
var checks := 0
var failures := 0
var native: Native
var files: Array[String] = []

class Native extends RefCounted:
	signal request_result(id: String, operation: String, payload: String)
	signal request_error(id: String, operation: String, code: String, message: String, cancelled: bool)
	signal customer_info_updated(payload: String)
	var calls: Array[Dictionary] = []
	func configure(_key: String, owner: String, _mode: String, id: String) -> void: calls.append({"operation":"configure", "id":id, "owner":owner})
	func get_customer_info(id: String) -> void: calls.append({"operation":"get_customer_info", "id":id})
	func get_offerings(id: String) -> void: calls.append({"operation":"get_offerings", "id":id})
	func purchase_package(_offering: String, _package: String, id: String) -> void: calls.append({"operation":"purchase_package", "id":id})
	func restore_purchases(id: String) -> void: calls.append({"operation":"restore_purchases", "id":id})
	func answer(call: Dictionary, payload: Dictionary) -> void: request_result.emit(call.id, call.operation, JSON.stringify(payload))
	func count(operation: String) -> int:
		var total := 0
		for call: Dictionary in calls:
			if call.operation == operation: total += 1
		return total

class Secrets extends Node:
	signal completed(id: String, operation: String, payload: Dictionary)
	signal failed(id: String, operation: String, code: String)
	var serial := 0
	var token := TOKEN
	func is_available() -> bool: return true
	func get_secret(name: String) -> String:
		serial += 1
		var id := "session-secret-%d" % serial
		var payload := {"found":false, "value":null}
		if name == "player_identity": payload = {"found":true, "value":JSON.stringify({"player_id":OWNER, "device_token":token})}
		completed.emit.call_deferred(id, "get", payload)
		return id

class ReadApi extends Node:
	signal entered
	signal released
	var base_url := ""
	var player_id := ""
	var device_token := ""
	var calls := 0
	var tally := {"calls":0}
	func request_json(method: int, path: String, body: Dictionary = {}) -> Dictionary:
		assert(method == HTTPClient.METHOD_GET and path == "/v1/entitlement" and body.is_empty())
		calls += 1
		tally.calls += 1
		entered.emit.call_deferred()
		await released
		return {"ok":true,"status":200,"data":{"full_journey":true,"status":"verified","access_source":"review_grant","entitlement":"full_journey_play","player_id":OWNER}}

class Screen extends Main:
	func _tester_checks_enabled() -> bool: return false

class LighthouseGate extends Lighthouse:
	# Keep the real admission methods; rendering/journal loading have their own suite.
	func _ready() -> void:
		_purchase_gate = true
		_access_granted = false
		mode = "loading"
		set_process(false)
		set_physics_process(false)
	func _show_access_hold(_message: String) -> void: mode = "loading"
	func _begin_journal_load() -> void: _journal_started = true

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280,720)
	native = Native.new()
	await _navigation()
	await _broker_races()
	await _explicit_scene_checks()
	await _promotional_readers()
	Session.suspend_shared(true)
	Review.forget_shared()
	await process_frame
	for path: String in files:
		for suffix: String in ["", ".tmp", ".backup"]:
			if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	print("PURCHASE SESSION: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _payload(active: bool = true, owner: String = OWNER, store: String = "PLAY_STORE") -> Dictionary:
	return {"schema_version":1,"mode":"google_play","player_id":owner,"request_date_ms":1000,
		"entitlements":{"full_journey_play":{"active":active,"store":store,"product_id":Purchases.PLAY_PRODUCT}}}

func _facade() -> Node:
	var service := Purchases.new()
	service._configuration = CONFIG.duplicate(true)
	service.native_factory = func(): return native
	return service

func _screen() -> Node:
	var screen := Screen.new()
	var path := "user://purchase-session-%d.json" % Time.get_ticks_usec()
	files.append(path)
	screen.saves = Storage.new(path)
	screen.saves.data.settings.sound = false
	screen.saves.data.settings.haptics = false
	screen.saves.flush()
	root.add_child(screen)
	screen.set_process(false)
	screen.set_physics_process(false)
	screen.world.set_process(false)
	await process_frame
	await process_frame
	screen.purchases.free()
	screen.secrets.free()
	screen.config.merge(CONFIG, true)
	screen.api.base_url = CONFIG.api_base_url
	var service := _facade()
	screen.purchases = service
	screen.add_child(service)
	service.completed.connect(screen._purchase_completed)
	service.failed.connect(screen._purchase_failed)
	service.customer_info_changed.connect(screen._customer_info_changed)
	var secrets := Secrets.new()
	screen.secrets = secrets
	screen.add_child(secrets)
	secrets.completed.connect(screen._secret_completed)
	secrets.failed.connect(screen._secret_failed)
	screen.identity_loading = false
	screen._load_saved_identity()
	for frame in range(4): await process_frame
	return screen

func _navigation() -> void:
	Session.suspend_shared(true)
	native.calls.clear()
	var first: Node = await _screen()
	_check(native.count("configure") == 1 and not first.store_configured, "Initial Main performs one provider configuration before admission")
	native.answer(native.calls[-1], _payload())
	await process_frame
	_check(first._store_identity_ready(), "Actual Main completion accepts the current configured identity")
	first.queue_free()
	await process_frame
	var gate := Access.new()
	gate.purchase_service_factory = _facade
	root.add_child(gate)
	gate.check_access()
	_check(not gate.is_granted(), "Cached admission remains deferred until the caller retains its request ID")
	await process_frame
	_check(gate.is_granted() and native.calls.size() == 1, "Paid chapter reuses initial configuration without another native customer read")
	gate.set_backgrounded(true)
	gate.set_backgrounded(false)
	await process_frame
	_check(gate.is_granted() and native.calls.size() == 1, "Normal Play foreground return reuses session data without polling")
	gate.queue_free()
	await process_frame
	var second: Node = await _screen()
	_check(second._store_identity_ready() and native.calls.size() == 1, "Returning Main rechecks secure identity and reuses the same session without native reconfiguration")
	second._invalidate_relay_identity(false)
	second.identity_read_state = second.IdentityReadState.FAILED
	second.store_configured = false
	second._configure_purchases()
	await process_frame
	_check(native.calls.size() == 1 and not second.purchases.has_entitlement(), "Retained credentials cannot release the session hold after secure identity reread fails")
	second._load_saved_identity()
	for frame in range(4): await process_frame
	_check(second._store_identity_ready() and native.calls.size() == 1, "A successful same-credential reread restores the retained session")
	second._show_paywall()
	await process_frame
	_check(native.calls.size() == 1, "Repeated buyer paywall navigation does not query the provider")
	second._show_paywall()
	second._load_store(true)
	_check(native.count("get_customer_info") == 1, "Explicit Retry store requests fresh customer information")
	native.answer(native.calls[-1], _payload())
	await process_frame
	second.queue_free()
	await process_frame

func _broker_races() -> void:
	Session.suspend_shared(true)
	native.calls.clear()
	var owner := _facade()
	var follower := _facade()
	root.add_child(owner)
	owner.bind_session(OWNER, TOKEN)
	root.add_child(follower)
	var received: Array = []
	var errors: Array = []
	follower.completed.connect(func(id,operation,payload): received.append([id,operation,payload]))
	follower.failed.connect(func(id,operation,code,_message,_cancelled): errors.append([id,operation,code]))
	owner.configure_store(CONFIG.revenuecat_public_key, OWNER, CONFIG.purchase_mode)
	var request: String = follower.refresh_customer_info()
	_check(native.calls.size() == 1, "A second reader joins the initial configuration instead of sending a parallel read")
	owner.free()
	native.answer(native.calls[-1], _payload(false))
	await process_frame
	_check(received.size() == 1 and received[0][0] == request and not follower.has_entitlement(), "The root broker settles its surviving reader after the original scene is destroyed")
	follower.refresh_customer_info()
	await process_frame
	_check(received.size() == 2 and native.calls.size() == 1, "Valid negative provider results are reused without becoming an unlock")
	follower.refresh_customer_info_fresh()
	var stale := native.calls[-1]
	var restored: String = follower.restore()
	var restore_call := native.calls[-1]
	native.answer(restore_call, _payload())
	native.answer(stale, _payload(false))
	await process_frame
	_check(follower.has_entitlement() and received[-1][0] == restored, "An earlier delayed read cannot overwrite a successful restore")
	var reads := native.count("get_customer_info")
	follower.refresh_customer_info()
	await process_frame
	_check(follower.has_entitlement() and native.count("get_customer_info") == reads, "Restore replaces the shared result for later navigation")
	var restore_again: String = follower.restore()
	var pending_restore := native.calls[-1]
	follower.refresh_customer_info()
	follower.refresh_customer_info_fresh()
	follower.invalidate_session_reads()
	_check(native.calls[-1] == pending_restore, "Normal and forced reads wait behind an issued restore instead of racing its result")
	var bought := _payload()
	bought.request_date_ms = 2000
	native.answer(pending_restore, bought)
	_check(received[-1][0] == restore_again and received[-1][2].entitlements.full_journey_play.active, "Cache invalidation cannot orphan an issued restore; the caller settles with the purchase result")
	_check(native.count("get_customer_info") == reads + 1, "Queued explicit refresh starts one provider read after restore settles")
	native.answer(native.calls[-1], _payload(false))
	await process_frame
	_check(follower.has_entitlement(), "An older negative provider result cannot overwrite newer restored customer information")
	native.customer_info_updated.emit(JSON.stringify(_payload(false)))
	_check(follower.has_entitlement(), "An older unsolicited SDK update cannot undo a newer restore")
	reads = native.count("get_customer_info")
	var revoked := _payload(false)
	revoked.request_date_ms = 3000
	native.customer_info_updated.emit(JSON.stringify(revoked))
	follower.refresh_customer_info()
	await process_frame
	_check(not follower.has_entitlement() and native.count("get_customer_info") == reads, "SDK revocation replaces cached access and notifies the current facade")
	follower.refresh_customer_info_fresh()
	var failed_call := native.calls[-1]
	native.request_error.emit(failed_call.id, failed_call.operation, "offline", "Offline", false)
	follower.refresh_customer_info()
	_check(native.count("get_customer_info") == reads + 2, "Transient failure is not cached and the next attempt remains retryable")
	var malformed := _payload()
	malformed.erase("player_id")
	native.answer(native.calls[-1], malformed)
	follower.refresh_customer_info()
	_check(native.count("get_customer_info") == reads + 3 and not follower.has_entitlement(), "Malformed unbound provider payload does not seed a grant or negative cache")
	var before_rotation := native.calls[-1]
	Purchases.suspend_session(true)
	follower.bind_session(OWNER, "E".repeat(43))
	native.answer(before_rotation, _payload())
	await process_frame
	_check(not follower.has_entitlement(), "A late successful read from the prior credential cannot unlock the replacement scope")
	follower.configure_store(CONFIG.revenuecat_public_key, OWNER, CONFIG.purchase_mode)
	native.answer(native.calls[-1], _payload())
	await process_frame
	_check(follower.has_entitlement(), "Fixture has a positive current grant before scope retirement")
	var replacement := _facade()
	root.add_child(replacement)
	replacement.bind_session("N".repeat(22), "F".repeat(43))
	var before_old_facade := native.calls.size()
	follower.refresh_customer_info()
	follower.restore()
	follower.purchase("journey", "lifetime")
	native.customer_info_updated.emit(JSON.stringify(_payload(true, "N".repeat(22))))
	await process_frame
	_check(native.calls.size() == before_old_facade and not follower.has_entitlement(), "An old granted facade cannot read, purchase, restore, or adopt broadcasts for a replacement identity")
	replacement.configure_store(CONFIG.revenuecat_public_key, "N".repeat(22), CONFIG.purchase_mode)
	native.answer(native.calls[-1], _payload(true, "N".repeat(22)))
	await process_frame
	_check(replacement.has_entitlement() and not follower.has_entitlement(), "Only the explicitly bound replacement facade receives the new identity's confirmed grant")
	replacement.free()
	follower.bind_session(OWNER, "E".repeat(43))
	follower.configure_store(CONFIG.revenuecat_public_key, OWNER, CONFIG.purchase_mode)
	native.answer(native.calls[-1], _payload())
	await process_frame
	var before_hold := native.calls.size()
	Purchases.suspend_session(false)
	var held_revocation := _payload(false)
	held_revocation.request_date_ms = 2000
	native.customer_info_updated.emit(JSON.stringify(held_revocation))
	follower.bind_session(OWNER, "E".repeat(43))
	follower.configure_store(CONFIG.revenuecat_public_key, OWNER, CONFIG.purchase_mode)
	_check(native.calls.size() == before_hold + 1 and not follower.has_entitlement(), "A revocation during secure identity hold prevents replaying the old positive cache")
	native.answer(native.calls[-1], held_revocation)
	await process_frame
	_check(not follower.has_entitlement(), "Same-identity confirmation preserves the revocation observed during the hold")
	follower.refresh_customer_info_fresh()
	var renewed := _payload()
	renewed.request_date_ms = 3000
	native.answer(native.calls[-1], renewed)
	await process_frame
	var lost_restore: String = follower.restore()
	var lost_call := native.calls[-1]
	follower.refresh_customer_info()
	var broker: Node = Session.shared(self, native)
	broker._writes[lost_restore].deadline = 0
	broker._process(0.0)
	_check(errors[-1][0] == lost_restore and native.calls[-1].operation == "get_customer_info", "A missing mutation callback expires, settles its caller, and releases pending reads without retrying the mutation")
	native.answer(lost_call, _payload(false))
	native.answer(native.calls[-1], renewed)
	await process_frame
	_check(follower.has_entitlement(), "A retired mutation callback cannot alter recovered current customer information")
	var deliveries := received.size()
	follower.refresh_customer_info()
	Purchases.suspend_session(true)
	await process_frame
	_check(received.size() == deliveries and not errors.is_empty(), "Identity invalidation between cache scheduling and delivery rejects the cached completion")
	follower.free()

func _explicit_scene_checks() -> void:
	Session.suspend_shared(true)
	native.calls.clear()
	var owner := _facade()
	root.add_child(owner)
	owner.bind_session(OWNER, TOKEN)
	owner.configure_store(CONFIG.revenuecat_public_key, OWNER, CONFIG.purchase_mode)
	native.answer(native.calls[-1], _payload(false))
	await process_frame
	var gate := Access.new()
	gate.purchase_service_factory = _facade
	root.add_child(gate)
	gate.check_access()
	await process_frame
	_check(not gate.is_granted() and native.calls.size() == 1, "Chapter admission reuses a verified session denial")
	gate.check_access(true)
	_check(native.count("get_customer_info") == 1, "Chapter Check again explicitly bypasses that denial cache")
	native.answer(native.calls[-1], _payload(false))
	await process_frame
	gate.free()
	var lighthouse := LighthouseGate.new()
	lighthouse.purchase_service_factory = _facade
	root.add_child(lighthouse)
	lighthouse._check_access()
	await process_frame
	_check(not lighthouse._access_granted and native.count("get_customer_info") == 1, "Lighthouse entry shares the same verified denial")
	lighthouse._check_access(true)
	_check(native.count("get_customer_info") == 2, "Lighthouse Check purchase again requests fresh information")
	native.answer(native.calls[-1], _payload(false))
	await process_frame
	lighthouse.free()
	owner.free()

func _promotional_readers() -> void:
	Session.suspend_shared(true)
	Review.forget_shared()
	native.calls.clear()
	var verifier: Node = Review.shared(self)
	var secrets := Secrets.new()
	var api := ReadApi.new()
	verifier.secret_factory = func(): return secrets
	verifier.api_factory = func(): return api
	var first := _facade()
	var second := _facade()
	root.add_child(first)
	first.bind_session(OWNER, TOKEN)
	root.add_child(second)
	first.configure_store(CONFIG.revenuecat_public_key, OWNER, CONFIG.purchase_mode)
	second.refresh_customer_info()
	native.answer(native.calls[-1], _payload(true, OWNER, "PROMOTIONAL"))
	await api.entered
	_check(api.calls == 1 and not first.has_entitlement() and not second.has_entitlement(), "Concurrent promotional facades share one authenticated check and stay closed while it is pending")
	api.released.emit()
	var tally: Dictionary = api.tally
	for frame in range(12): await process_frame
	_check(first.has_entitlement() and second.has_entitlement() and tally.calls == 1, "One verified foreground proof satisfies both current promotional readers")
	first.free()
	second.free()
	# Free gameplay scenes have no purchase facade. The surviving verifier must
	# own its foreground proof lifetime independently of those destroyed scenes.
	verifier.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	var background_grant: bool = await verifier.verify(OWNER, CONFIG.api_base_url)
	_check(not background_grant and tally.calls == 1, "The shared verifier cannot start or reuse a promotional proof while the app is backgrounded without purchase facades")
	verifier.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	var resumed_api := ReadApi.new()
	resumed_api.tally = tally
	verifier.api_factory = func(): return resumed_api
	var native_before := native.calls.size()
	Purchases.suspend_session(false)
	var resumed := _facade()
	root.add_child(resumed)
	resumed.bind_session(OWNER, TOKEN)
	resumed.configure_store(CONFIG.revenuecat_public_key, OWNER, CONFIG.purchase_mode)
	for frame in range(12): await process_frame
	_check(tally.calls == 2 and not resumed.has_entitlement() and native.calls.size() == native_before, "Returning after a facade-free background period reuses native customer information but requires a fresh authenticated promotional check")
	if resumed_api.calls == 1: resumed_api.released.emit()
	for frame in range(12): await process_frame
	_check(resumed.has_entitlement() and tally.calls == 2, "Promotional access resumes only after the new foreground verification succeeds")
	resumed.free()
	if is_instance_valid(resumed_api): resumed_api.free()
	verifier.free()

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
