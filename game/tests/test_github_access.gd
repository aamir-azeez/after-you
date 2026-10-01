extends SceneTree

const Main = preload("res://main.gd")
const Purchases = preload("res://services/purchases.gd")
const Access = preload("res://services/chapter_access.gd")
const Storage = preload("res://services/local_save.gd")
const Session = preload("res://services/purchase_session.gd")
const LOCKED := {"purchase_mode":"tester_only","entitlement_id":"full_journey","revenuecat_public_key":""}
const TEST_CONFIG := {"purchase_mode":"test_store","entitlement_id":"full_journey","revenuecat_public_key":"test_github_key","api_base_url":"https://example.invalid"}
const OWNER := "PPPPPPPPPPPPPPPPPPPPPP"
const TOKEN := "DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD"
const OLD := {"schema_version":1,"mode":"test_store","entitlements":{"full_journey":{"active":true,"store":"TEST_STORE"}}}
var checks := 0
var failures := 0
var path := "user://github-access-%d.json" % Time.get_ticks_usec()

class Probe extends Purchases:
	var connects := 0
	func _connect_native() -> bool:
		connects += 1
		return false

class Screen extends Main:
	var play_links := 0
	var code_links := 0
	func _tester_checks_enabled() -> bool: return false
	func _open_google_play() -> void: play_links += 1
	func _show_tester_access() -> void: code_links += 1

class TestScreen extends Screen:
	func _ensure_identity() -> bool: return true

class Native extends RefCounted:
	signal request_result(id: String, operation: String, payload: String)
	signal request_error(id: String, operation: String, code: String, message: String, cancelled: bool)
	signal customer_info_updated(payload: String)
	var calls: Array[Dictionary] = []
	func configure(_key: String, owner: String, mode: String, id: String) -> void: calls.append({"operation":"configure","id":id,"owner":owner,"mode":mode})
	func get_customer_info(id: String) -> void: calls.append({"operation":"get_customer_info","id":id})
	func get_offerings(id: String) -> void: calls.append({"operation":"get_offerings","id":id})
	func purchase_package(offering: String, package: String, id: String) -> void: calls.append({"operation":"purchase_package","id":id,"offering":offering,"package":package})
	func restore_purchases(id: String) -> void: calls.append({"operation":"restore_purchases","id":id})
	func answer(payload: Dictionary) -> void:
		var call: Dictionary = calls[-1]
		request_result.emit(call.id,call.operation,JSON.stringify(payload))

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280,720)
	await _provider_boundary()
	await _menu_boundary()
	await _test_store_menu()
	Session.suspend_shared(true)
	await create_timer(0.15).timeout
	for suffix: String in ["", ".tmp", ".backup"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	print("GITHUB ACCESS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _provider_boundary() -> void:
	for configuration: Dictionary in [LOCKED, {"purchase_mode":"test_store","entitlement_id":"full_journey_play","revenuecat_public_key":"test_mismatched_key"}, {}]:
		var service := Probe.new()
		service._configuration = configuration.duplicate(true)
		root.add_child(service)
		var initial := service.connects
		var errors: Array = []
		var results: Array = []
		service.failed.connect(func(id,operation,code,_message,_cancelled): errors.append([id,operation,code]))
		service.completed.connect(func(id,operation,_payload): results.append([id,operation]))
		service.customer_info = OLD.duplicate(true)
		_check(not service.has_entitlement() and not service.is_available(), "Old SDK cache and native availability cannot unlock a restricted configuration")
		var requests := [service.configure_store("test_retired_key","P".repeat(22),"test_store"),service.fetch_offerings(),service.refresh_customer_info(),service.purchase("journey","lifetime"),service.restore()]
		service._on_result(requests[-1],"restore_purchases",JSON.stringify(OLD))
		service._on_customer_info(JSON.stringify(OLD))
		await process_frame
		_check(errors.size() == 5 and results.is_empty() and service.connects == initial, "Configure, offers, refresh, buy and restore all settle without entering the native store")
		for error: Array in errors: _check(error[2] == "store_disabled", "Restricted provider request fails explicitly")
		_check(not service.has_entitlement() and service._pending.is_empty(), "Late old restore and customer-info callbacks leave access closed")
		service.queue_free()
		await process_frame
	var store := Purchases.new()
	store._configuration = LOCKED.duplicate(true)
	store.customer_info = OLD.duplicate(true)
	var gate := Access.new()
	gate.purchase_service_factory = func(): return store
	root.add_child(gate)
	gate.check_access()
	await process_frame
	_check(gate.state == "hold" and not gate.is_granted(), "Direct paid scene admission rejects retained Test Store access")
	gate.set_backgrounded(true)
	gate.set_backgrounded(false)
	await process_frame
	_check(not gate.is_granted(), "Returning from background does not restore the retired store grant")
	gate.queue_free()
	await process_frame

func _menu_boundary() -> void:
	var screen := Screen.new()
	screen.saves = Storage.new(path)
	root.add_child(screen)
	screen.set_process(false)
	screen.set_physics_process(false)
	screen.world.set_process(false)
	screen.config.merge(LOCKED,true)
	screen.purchases._configuration = LOCKED.duplicate(true)
	screen.purchases.customer_info = OLD.duplicate(true)
	var before := screen.saves.data.duplicate(true)
	screen._start_practice(3)
	_check(screen.mode == "paywall" and not screen.running, "A retained Test Store buyer reaches the paywall for an earlier paid island")
	_check(_button(screen.overlay,"Get it on Google Play") != null and _button(screen.overlay,"Tester code") != null, "Restricted paywall offers the store download and tester code")
	_check(_button(screen.overlay,"Restore purchases") == null and _button(screen.overlay,"Retry store") == null, "Restricted paywall offers no retired free store actions")
	_button(screen.overlay,"Get it on Google Play").pressed.emit()
	_button(screen.overlay,"Tester code").pressed.emit()
	_check(screen.play_links == 1 and screen.code_links == 1, "Both visible access actions invoke their real controller routes")
	screen.purchase_package = {"offering_id":"old","id":"old","price":"Free"}
	screen._buy_full_journey()
	await screen._restore_store()
	await screen._load_store()
	await screen._configure_purchases(true)
	screen._purchase_completed("old","configure",OLD)
	_check(not screen.store_configured and not screen.store_action_pending and screen.purchases._pending.is_empty(), "Direct old store controller actions cannot configure or buy")
	screen._show_store_offer()
	_check(_button(screen.overlay,"Get it on Google Play") != null, "An old offering callback cannot recreate the free checkout")
	_check(screen.saves.data == before, "Denied access preserves the complete local saved game")
	screen._start_practice(0)
	_check(screen.mode == "ready", "The free opening island remains playable")
	screen.queue_free()
	await process_frame
	await process_frame

func _test_store_menu() -> void:
	Session.suspend_shared(true)
	var native := Native.new()
	var screen := TestScreen.new()
	screen.saves = Storage.new(path)
	root.add_child(screen)
	screen.set_process(false)
	screen.set_physics_process(false)
	screen.world.set_process(false)
	for frame in range(3): await process_frame
	screen.purchases.free()
	var service := Purchases.new()
	service._configuration = TEST_CONFIG.duplicate(true)
	service.native_factory = func(): return native
	screen.purchases = service
	screen.add_child(service)
	service.completed.connect(screen._purchase_completed)
	service.failed.connect(screen._purchase_failed)
	service.customer_info_changed.connect(screen._customer_info_changed)
	screen.config.merge(TEST_CONFIG,true)
	screen.api.base_url = TEST_CONFIG.api_base_url
	screen.api.player_id = OWNER
	screen.api.device_token = TOKEN
	screen.identity_read_state = screen.IdentityReadState.LOADED
	screen.identity_loading = false
	screen._show_paywall()
	for frame in range(3): await process_frame
	_check(_button(screen.overlay,"Get it on Google Play") == null and _button(screen.overlay,"Restore purchases") != null, "Test Store paywall opens in-app purchasing and restore without redirecting to Play")
	_check(native.calls.size() == 1 and native.calls[-1].operation == "configure" and native.calls[-1].mode == "test_store", "The GitHub paywall configures the native Test Store provider")
	if native.calls.is_empty():
		screen.queue_free()
		await process_frame
		return
	native.answer(_test_payload(false))
	for frame in range(3): await process_frame
	_check(native.calls[-1].operation == "get_offerings", "The configured GitHub paywall requests the provider's current offering")
	native.answer({"schema_version":1,"mode":"test_store","current_id":"journey","offerings":[
		{"id":"journey","packages":[{"id":"lifetime","type":"LIFETIME","product_id":Purchases.TEST_PRODUCT,"price":"$4.99"}]}]})
	for frame in range(3): await process_frame
	_check(screen.purchase_package.get("product_id") == Purchases.TEST_PRODUCT and not service.has_entitlement(), "Viewing the Test Store lifetime offer does not grant access")
	screen._buy_full_journey()
	_check(native.calls[-1].operation == "purchase_package" and native.calls[-1].get("offering") == "journey" and native.calls[-1].get("package") == "lifetime", "The GitHub buy action purchases the exact native offering and package")
	native.answer(_test_payload())
	for frame in range(3): await process_frame
	_check(service.has_entitlement() and not screen.store_action_pending and screen._full_journey_access(), "Only the provider purchase callback unlocks the Test Store journey")
	screen._restore_store()
	_check(native.calls[-1].operation == "restore_purchases", "GitHub restore invokes the native provider")
	native.answer(_test_payload())
	for frame in range(3): await process_frame
	_check(service.has_entitlement() and not screen.store_action_pending, "The native restore callback confirms the Test Store entitlement")
	screen.queue_free()
	await process_frame
	await process_frame

func _test_payload(active: bool = true) -> Dictionary:
	return {"schema_version":1,"mode":"test_store","player_id":OWNER,"request_date_ms":1000,
		"entitlements":{"full_journey":{"active":active,"store":"TEST_STORE","product_id":Purchases.TEST_PRODUCT}}}

func _button(node: Node, label: String) -> Button:
	if node is Button and node.text == label: return node
	for child: Node in node.get_children():
		var found := _button(child,label)
		if found != null: return found
	return null

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
