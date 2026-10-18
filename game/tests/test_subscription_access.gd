extends SceneTree
## Full Journey subscription states seen by the client: monthly, yearly, grace,
## expired, the grandfathered one-time product and no purchase, plus the
## subscriber's Manage, Restore and Settings paths. Test doubles only.

const Main = preload("res://main.gd")
const Purchases = preload("res://services/purchases.gd")
const ChapterAccess = preload("res://services/chapter_access.gd")
const Storage = preload("res://services/local_save.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")

const PLAY := {"purchase_mode":"google_play","entitlement_id":"full_journey_play"}
const TEST := {"purchase_mode":"test_store","entitlement_id":"full_journey"}
const NOW_MS := 1_800_000_000_000

class RestoreProbe extends Purchases:
	var restores := 0
	var restore_answer: Dictionary = {}
	func _connect_native() -> bool: return false
	func is_available() -> bool: return true
	func restore() -> String:
		restores += 1
		return "restore-%d" % restores

var checks := 0
var failures := 0
var paths: Array[String] = []

func _initialize() -> void: _run.call_deferred()

static func payload(entry: Variant, mode: String = "google_play", entitlement: String = "full_journey_play") -> Dictionary:
	var entitlements := {}
	if entry is Dictionary: entitlements[entitlement] = entry
	return {"schema_version":1,"mode":mode,"player_id":"p".repeat(22),"request_date_ms":NOW_MS,"entitlements":entitlements}

static func play_entry(product: String, active: bool, expires_ms: Variant) -> Dictionary:
	return {"active":active,"store":"PLAY_STORE","product_id":product,"sandbox":false,"expires_at_ms":expires_ms,"verification":"NOT_REQUESTED"}

func _run() -> void:
	_entitlement_states()
	await _chapter_access_states()
	await _subscriber_screens()
	for path: String in paths:
		for suffix: String in ["", ".tmp", ".backup"]:
			if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	print("SUBSCRIPTION ACCESS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _entitlement_states() -> void:
	var states := [
		["active monthly", play_entry("after_you_full_journey_monthly", true, NOW_MS + 86400000), true, true],
		["active yearly with its base plan", play_entry("after_you_full_journey_yearly:yearly", true, NOW_MS + 86400000 * 300), true, true],
		# During Google's grace period RevenueCat keeps the entitlement active even
		# though the paid period has ended; the client trusts the SDK, not a clock.
		["grace period", play_entry("after_you_full_journey_monthly:monthly", true, NOW_MS - 3600000), true, true],
		["grandfathered one-time purchase", play_entry(Purchases.PLAY_PRODUCT, true, null), true, false],
		["expired subscription", play_entry("after_you_full_journey_monthly", false, NOW_MS - 86400000), false, false],
		["billing retry after grace", play_entry("after_you_full_journey_yearly", false, NOW_MS - 3600000), false, false],
		["no purchase", null, false, false],
	]
	for state: Array in states:
		var info := payload(state[1])
		_check(Purchases.entitled_for_configuration(info, PLAY) == state[2], "Play access for %s" % state[0])
		_check(Purchases.subscribed_for_configuration(info, PLAY) == state[3], "Manage subscription applies to %s only when it is a subscription" % state[0])
	for product: String in ["after_you_full_journey_weekly", "full_journey_monthly", "after_you_full_journey_monthly_extra", ""]:
		_check(not Purchases.entitled_for_configuration(payload(play_entry(product, true, null)), PLAY), "An unknown or Test Store product cannot unlock Play: " + product)
	var promotional := play_entry("after_you_full_journey_monthly", true, null)
	promotional.store = "PROMOTIONAL"
	_check(not Purchases.entitled_for_configuration(payload(promotional), PLAY), "A promotional grant still needs the separate reviewer check")
	var test_monthly := {"active":true,"store":"TEST_STORE","product_id":Purchases.TEST_SUBSCRIPTIONS[0]}
	_check(Purchases.entitled_for_configuration(payload(test_monthly, "test_store", "full_journey"), TEST), "A Test Store monthly subscription unlocks the Test Store build")
	test_monthly.product_id = Purchases.TEST_SUBSCRIPTIONS[1]
	_check(Purchases.entitled_for_configuration(payload(test_monthly, "test_store", "full_journey"), TEST), "A Test Store yearly subscription unlocks the Test Store build")
	test_monthly.product_id = Purchases.TEST_PRODUCT
	_check(Purchases.entitled_for_configuration(payload(test_monthly, "test_store", "full_journey"), TEST) and not Purchases.subscribed_for_configuration(payload(test_monthly, "test_store", "full_journey"), TEST), "Earlier Test Store one-time testers keep access")
	test_monthly.product_id = "after_you_full_journey_monthly"
	_check(not Purchases.entitled_for_configuration(payload(test_monthly, "test_store", "full_journey"), TEST), "A Play product name cannot unlock the Test Store build")
	test_monthly.product_id = Purchases.TEST_SUBSCRIPTIONS[0]
	_check(not Purchases.entitled_for_configuration(payload(test_monthly, "test_store", "full_journey"), PLAY), "A Test Store subscription never unlocks the Play build")
	for value: Variant in [null, 7, ["after_you_full_journey_monthly"]]:
		_check(Purchases.store_product(value).is_empty(), "A malformed product ID never matches: %s" % str(value))

func _chapter_access_states() -> void:
	# The solo chapter admission service reads the same shared rule.
	for state: Array in [["after_you_full_journey_monthly", true, "granted"], ["after_you_full_journey_yearly:yearly", true, "granted"], [Purchases.PLAY_PRODUCT, true, "granted"], ["after_you_full_journey_monthly", false, "hold"]]:
		var store := RestoreProbe.new()
		store._configuration = PLAY.duplicate(true)
		var access := ChapterAccess.new()
		access.purchase_service_factory = func() -> Node: return store
		root.add_child(access)
		access._check_purchase()
		var request := access._request
		store._on_result(request, "get_customer_info", JSON.stringify(payload(play_entry(state[0], state[1], NOW_MS + 1000))))
		await process_frame
		_check(access.state == state[2], "Chapter access for %s (%s) is %s" % [state[0], "active" if state[1] else "lapsed", state[2]])
		access.queue_free()
		await process_frame

func _subscriber_screens() -> void:
	root.size = Vector2i(1280, 720)
	var app := Main.new()
	app.saves = Storage.new(_path("subscriber"))
	root.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	app.world.set_process(false)
	app.purchases.queue_free()
	var store := RestoreProbe.new()
	store._configuration = PLAY.duplicate(true)
	app.purchases = store
	app.add_child(store)
	app.config.merge({"purchase_mode":"google_play","entitlement_id":"full_journey_play","revenuecat_public_key":"goog_synthetic","api_base_url":"https://after-you.example"}, true)
	app.store_flow.store_configured = true
	app.store_flow.store_owner = "p".repeat(22)
	app.api.player_id = app.store_flow.store_owner
	app.api.device_token = "d".repeat(43)
	app.identity_loading = false
	for i in range(3): await process_frame

	# Restore finds the player's subscription and unlocks without a new checkout.
	app.store_flow.show_paywall(true)
	app.store_flow.purchase_completed("offer", "get_offerings", {"current_id":"journey","offerings":[{"id":"journey","packages":[
		{"id":"$rc_monthly","type":"MONTHLY","product_id":"after_you_full_journey_monthly:monthly","price":"₹89.00"},
		{"id":"$rc_annual","type":"ANNUAL","product_id":"after_you_full_journey_yearly:yearly","price":"₹899.00"}]}]})
	_check(_button(app.overlay, "Subscribe · ₹89.00 a month") != null and _button(app.overlay, "Subscribe · ₹899.00 a year") != null, "The paywall shows each package with the store's own localized price")
	_check(_button(app.overlay, PlayerCopy.SUBSCRIPTION_PRIVACY) != null and _button(app.overlay, PlayerCopy.SUBSCRIPTION_MANAGE) == null, "A nonsubscriber sees the privacy policy and no Manage subscription")
	_check(not "$0.99" in _all_text(app.overlay) and not "$9.99" in _all_text(app.overlay), "No price is hard-coded in the paywall")
	_button(app.overlay, "Restore purchases").pressed.emit()
	await process_frame
	_check(store.restores == 1 and app.store_flow.store_action_pending, "Restore asks the store once")
	store.customer_info = payload(play_entry("after_you_full_journey_yearly", true, NOW_MS + 1000))
	app.store_flow.purchase_completed(app.store_flow.store_action_request, "restore_purchases", store.customer_info)
	_check(store.has_entitlement() and _label(app.overlay, "Full Journey unlocked.") != null, "Restoring an active yearly subscription unlocks Full Journey")
	var manage := _button(app.overlay, PlayerCopy.SUBSCRIPTION_MANAGE)
	_check(manage != null and manage.pressed.is_connected(app.store_flow._open_subscription_management) and _label(app.overlay, PlayerCopy.SUBSCRIPTION_ACTIVE) != null, "A Play subscriber can open Manage subscription from the unlocked screen")
	_check(Purchases.PLAY_SUBSCRIPTIONS_URL.begins_with("https://play.google.com/store/account/subscriptions") and "com.aamirazeez.afteryou" in Purchases.PLAY_SUBSCRIPTIONS_URL, "Manage subscription opens Google Play's subscription page for this app")
	_check(app._hosting_entitled(), "A Play subscription grants hosting")

	# Settings keeps a way back to Manage and Restore after Home hides the offer.
	app.settings_flow.show_settings("account")
	var entry := _button(app.overlay, "Full Journey")
	_check(entry != null, "Settings lists Full Journey for a store build")
	if entry != null:
		entry.pressed.emit()
		await process_frame
		_check(app.mode == "paywall" and app.store_flow.store_from_settings, "Settings opens the Full Journey store screen")
		store.customer_info = payload(play_entry(Purchases.PLAY_PRODUCT, true, null))
		app.store_flow._show_full_journey_unlocked()
		_check(_button(app.overlay, PlayerCopy.SUBSCRIPTION_MANAGE) == null and _button(app.overlay, "Restore purchases") != null, "A grandfathered one-time buyer sees Restore and no subscription to manage")
		var back := _button(app.overlay, "Back to settings")
		_check(back != null, "The store opened from Settings returns to Settings")
		if back != null:
			back.pressed.emit()
			_check(app.settings_flow.showing("account") and not app.store_flow.store_from_settings, "Back from the store lands on Settings, at Account & recovery")
	app.store_flow.show_paywall()
	_check(not app.store_flow.store_from_settings, "Opening the store from anywhere else returns to chapters")

	# A lapsed subscription locks again and offers the subscriptions.
	store.customer_info = payload(play_entry("after_you_full_journey_monthly", false, NOW_MS - 1000))
	_check(not store.has_entitlement() and not app._hosting_entitled() and not app._full_journey_access(), "An expired subscription locks paid chapters and hosting again")
	app.config.purchase_mode = "tester_only"
	app.settings_flow.show_settings("account")
	_check(_button(app.overlay, "Full Journey") == null, "A build without a store has no Full Journey settings entry")
	root.remove_child(app)
	app.queue_free()
	await process_frame

func _path(name: String) -> String:
	var path := "user://test-subscription-%s-%d.json" % [name, Time.get_ticks_usec()]
	paths.append(path)
	return path

func _button(node: Node, text: String) -> Button:
	for button: Button in node.find_children("*", "Button", true, false):
		# A Settings row reads its label out instead of showing text.
		if button.text == text or (button.text.is_empty() and button.accessibility_name == text): return button
	return null

func _label(node: Node, text: String) -> Label:
	for label: Label in node.find_children("*", "Label", true, false):
		if label.text == text: return label
	return null

func _all_text(node: Node) -> String:
	var parts: PackedStringArray = []
	for control: Node in node.find_children("*", "", true, false):
		if control is Label or control is Button: parts.append(control.text)
	return "\n".join(parts)

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
