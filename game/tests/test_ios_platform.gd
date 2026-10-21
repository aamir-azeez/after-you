extends SceneTree
## iOS behaviour from shared code, with a fake AfterYouIOS singleton: the platform helper,
## platform copy, store gating, the native plugin lookup, invite links in the forms Universal
## Links deliver, the licence list, and the iOS paywall and settings. Android wording stays
## byte-identical everywhere else.

const Main = preload("res://main.gd")
const PlatformSupport = preload("res://services/platform_support.gd")
const NativeBridge = preload("res://services/native_bridge.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const Purchases = preload("res://services/purchases.gd")
const Secrets = preload("res://services/secure_store.gd")
const InviteShare = preload("res://services/invite_share.gd")
const InviteLinkBridge = preload("res://services/invite_link_bridge.gd")
const NotificationBridge = preload("res://services/turn_notification_bridge.gd")
const ShareCodes = preload("res://services/share_codes.gd")
const Licenses = preload("res://services/licenses.gd")
const Storage = preload("res://services/local_save.gd")
const GamesProvider = preload("res://services/platform_games/native_games_provider.gd")

const APP_STORE := {"purchase_mode": "app_store", "entitlement_id": "full_journey_play", "revenuecat_public_key": "appl_synthetic_key"}
const GOOGLE_PLAY := {"purchase_mode": "google_play", "entitlement_id": "full_journey_play", "revenuecat_public_key": "goog_synthetic_key"}
const TEST_STORE := {"purchase_mode": "test_store", "entitlement_id": "full_journey", "revenuecat_public_key": "test_synthetic_key"}
const TESTER_ONLY := {"purchase_mode": "tester_only", "entitlement_id": "full_journey", "revenuecat_public_key": ""}
const PLATFORM_WORDS := ["Android", "Google", "Play Store", "Play Console", "APK"]

var checks := 0
var failures := 0
var paths: Array[String] = []

## The iOS plugin's surface: the same names and signals as AfterYouAndroid.
class FakeIOS extends Object:
	signal secure_result(request_id: String, operation: String, payload_json: String)
	signal secure_error(request_id: String, operation: String, code: String)
	signal request_result(request_id: String, operation: String, payload_json: String)
	signal request_error(request_id: String, operation: String, code: String, message: String, cancelled: bool)
	signal customer_info_updated(payload_json: String)
	signal notification_result(request_id: String, operation: String, payload_json: String)
	signal notification_error(request_id: String, operation: String, code: String)
	signal notification_received(payload_json: String)
	signal notification_token_changed(payload_json: String)
	signal invite_link_available
	signal games_result(request_id: String, operation: String, payload_json: String)
	signal games_error(request_id: String, operation: String, code: String)
	signal games_account_changed(payload_json: String)
	var calls: Array = []
	var pending_link := ""
	func secure_put(name: String, value: String, request_id: String) -> void: calls.append(["secure_put", name, value, request_id])
	func secure_get(name: String, request_id: String) -> void: calls.append(["secure_get", name, request_id])
	func share_text(text: String) -> void: calls.append(["share_text", text])
	func invite_link_take() -> String:
		var value := pending_link
		pending_link = ""
		return value
	func games_available() -> bool: return true
	func games_status(request_id: String) -> void:
		calls.append(["games_status", request_id])
		games_result.emit.call_deferred(request_id, "status", JSON.stringify({"signed_in": true, "player_key": "f".repeat(64)}))
	func games_credential(web_client_id: String, request_id: String) -> void:
		calls.append(["games_credential", web_client_id, request_id])
		games_error.emit.call_deferred(request_id, "credential", "Some platform text that must not reach players")
	func notification_status(request_id: String) -> void:
		calls.append(["notification_status", request_id])
		notification_result.emit.call_deferred(request_id, "status", JSON.stringify({"supported": false, "configured": false}))

## Main with tester checks and identity readiness set by the test.
class App extends Main:
	func _tester_checks_enabled() -> bool: return false
	func _tester_active() -> bool: return false
	func _relay_identity() -> Dictionary: return {"ready": true, "player_id": "P".repeat(22), "epoch": 1}

class FakeStore extends Purchases:
	var entitled := false
	func _connect_native() -> bool: return true
	func is_available() -> bool: return true
	func has_entitlement(_entitlement_id: String = "") -> bool: return entitled
	func has_subscription() -> bool: return entitled

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 720)
	_platform_helper()
	_platform_copy()
	_store_rules()
	_licenses()
	await _native_services()
	await _paywall_and_settings()
	PlatformSupport.override_platform = ""
	PlatformSupport.override_release = false
	for path: String in paths:
		for suffix: String in ["", ".tmp", ".bak"]:
			if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	print("AFTER YOU iOS PLATFORM: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _platform_helper() -> void:
	_check(PlatformSupport.platform() == PlatformSupport.DESKTOP and not PlatformSupport.is_ios() and not PlatformSupport.is_phone(), "The test runner is a desktop build")
	_check(PlatformSupport.tester_code_offered() and PlatformSupport.play_listing_offered(), "Desktop keeps Tester code and the Google Play link")
	PlatformSupport.override_platform = PlatformSupport.IOS
	_check(PlatformSupport.is_ios() and PlatformSupport.is_phone() and PlatformSupport.store_gated(), "iOS is a phone with store-gated chapters")
	_check(not PlatformSupport.play_listing_offered(), "iOS never links to Google Play")
	_check(not PlatformSupport.tester_code_offered_for(false) and PlatformSupport.tester_code_offered_for(true), "iOS offers Tester code in debug builds only")
	PlatformSupport.override_platform = PlatformSupport.ANDROID
	_check(PlatformSupport.is_phone() and not PlatformSupport.is_ios() and PlatformSupport.tester_code_offered_for(false) and PlatformSupport.play_listing_offered(), "Android keeps Tester code and Google Play in every build")
	PlatformSupport.override_platform = ""

func _platform_copy() -> void:
	var pairs := [
		[PlayerCopy.MAIN_3E8E7DA4CEE6, PlayerCopy.MAIN_3E8E7DA4CEE6_IOS],
		[PlayerCopy.MAIN_F890477C65DE, PlayerCopy.MAIN_F890477C65DE_IOS],
		[PlayerCopy.MAIN_570EC629872D, PlayerCopy.MAIN_570EC629872D_IOS],
		[PlayerCopy.MAIN_EF43E19393E4, PlayerCopy.MAIN_EF43E19393E4_IOS],
		[PlayerCopy.MAIN_B39BBA0B04B0, PlayerCopy.MAIN_B39BBA0B04B0_IOS],
		[PlayerCopy.PURCHASES_49387E2DE82E, PlayerCopy.PURCHASES_49387E2DE82E_IOS],
		[PlayerCopy.TURN_NOTIFICATIONS_6B57E7FA9822, PlayerCopy.TURN_NOTIFICATIONS_6B57E7FA9822_IOS],
		[PlayerCopy.TURN_NOTIFICATIONS_5015371169FE, PlayerCopy.TURN_NOTIFICATIONS_5015371169FE_IOS],
		[PlayerCopy.TURN_NOTIFICATIONS_3B300B883B57, PlayerCopy.TURN_NOTIFICATIONS_3B300B883B57_IOS],
		[PlayerCopy.SUBSCRIPTION_ACTIVE, PlayerCopy.SUBSCRIPTION_ACTIVE_IOS],
		[PlayerCopy.SUBSCRIPTION_TERMS_PLAY, PlayerCopy.SUBSCRIPTION_TERMS_APP_STORE],
	]
	_check(PlayerCopy.MAIN_3E8E7DA4CEE6 == "Online identity storage requires the Android app." and PlayerCopy.SUBSCRIPTION_ACTIVE == "Your subscription pays for hosting and server costs. You can change or cancel it in Google Play.", "The Android wording is unchanged")
	for platform: String in ["", PlatformSupport.ANDROID, PlatformSupport.IOS]:
		PlatformSupport.override_platform = platform
		for pair: Array in pairs:
			var expected: String = pair[1] if platform == PlatformSupport.IOS else pair[0]
			_check(PlayerCopy.for_platform(pair[0], pair[1]) == expected, "Platform copy for %s picks the right text: %s" % [platform if not platform.is_empty() else "desktop", expected.left(40)])
	PlatformSupport.override_platform = ""
	var ios_texts: Array = pairs.map(func(pair: Array) -> String: return pair[1])
	ios_texts.append_array([PlayerCopy.MAIN_C93C27D9AB17_NO_TESTER, PlayerCopy.SUBSCRIPTION_TERMS_OF_USE, PlayerCopy.SETTINGS_ACCOUNT_SUMMARY_FREE])
	for text: String in ios_texts:
		_check(not text.is_empty(), "iOS copy is never empty")
		for word: String in PLATFORM_WORDS:
			_check(not text.contains(word), "iOS copy names no other platform (%s): %s" % [word, text.left(40)])
		_check(not text.contains("—") and not text.contains("–"), "iOS copy uses no dashes: " + text.left(40))
	_check(PlayerCopy.MAIN_C93C27D9AB17.begins_with(PlayerCopy.MAIN_C93C27D9AB17_NO_TESTER) and not PlayerCopy.MAIN_C93C27D9AB17_NO_TESTER.contains("Tester"), "Without Tester code the recovery message drops only its tester sentence")

func _store_rules() -> void:
	var app_payload := {"schema_version": 1, "mode": "app_store", "entitlements": {"full_journey_play": {"active": true, "store": "APP_STORE", "product_id": "after_you_full_journey_yearly_ios"}}}
	for platform: String in ["", PlatformSupport.ANDROID]:
		PlatformSupport.override_platform = platform
		_check(Purchases.store_enabled(GOOGLE_PLAY) and Purchases.store_enabled(TEST_STORE) and not Purchases.store_enabled(TESTER_ONLY), "Google Play and Test Store stay enabled outside iOS")
		_check(not Purchases.store_enabled(APP_STORE) and not Purchases.entitled_for_configuration(app_payload, APP_STORE), "The App Store is never enabled outside iOS")
		_check(Purchases.subscriptions_url(GOOGLE_PLAY) == Purchases.PLAY_SUBSCRIPTIONS_URL, "Google Play subscribers manage in Google Play")
	PlatformSupport.override_platform = PlatformSupport.IOS
	_check(not Purchases.store_enabled(GOOGLE_PLAY), "A Google Play configuration is unavailable on iOS")
	_check(Purchases.store_enabled(APP_STORE) and Purchases.store_enabled(TEST_STORE) and not Purchases.store_enabled(TESTER_ONLY), "iOS sells through the App Store or RevenueCat's Test Store")
	_check(Purchases.entitled_for_configuration(app_payload, APP_STORE), "An active App Store subscription unlocks Full Journey on iOS")
	var other_store := app_payload.duplicate(true)
	other_store.entitlements.full_journey_play.store = "PLAY_STORE"
	_check(not Purchases.entitled_for_configuration(other_store, APP_STORE), "A Play Store record cannot unlock the App Store configuration on the client")
	var test_receipt := app_payload.duplicate(true)
	test_receipt.mode = "test_store"
	test_receipt.entitlements.full_journey_play.store = "TEST_STORE"
	_check(not Purchases.entitled_for_configuration(test_receipt, APP_STORE), "A Test Store receipt never unlocks the App Store configuration")
	_check(not Purchases.admitted_product(Purchases.PLAY_PRODUCT, APP_STORE) and Purchases.admitted_product("after_you_full_journey_monthly_ios", APP_STORE), "The App Store admits only its two subscriptions")
	_check(Purchases.subscriptions_url(APP_STORE) == "https://apps.apple.com/account/subscriptions" and Purchases.subscriptions_url(GOOGLE_PLAY).is_empty(), "App Store subscribers manage in the App Store")
	_check(not Purchases.review_candidate(app_payload, APP_STORE), "The Play reviewer path does not apply on iOS")
	PlatformSupport.override_platform = ""

func _licenses() -> void:
	var desktop_titles: Array = Licenses.entries().map(func(entry: Dictionary) -> String: return entry.title)
	_check(desktop_titles.has("RevenueCat Android 10.15.1") and desktop_titles.has("LLVM Android runtime") and desktop_titles.has("Android SDK license"), "Android and desktop keep the Android notices")
	PlatformSupport.override_platform = PlatformSupport.IOS
	var ios_titles: Array = Licenses.entries().map(func(entry: Dictionary) -> String: return entry.title)
	for title: String in Licenses.ANDROID_ONLY:
		_check(not ios_titles.has(title), "iOS leaves out the Android notice: " + title)
	_check(not ios_titles.has("LLVM Android runtime"), "iOS leaves out the Android C++ runtime notices")
	_check(ios_titles.has("After You") and ios_titles.has("Godot Engine") and ios_titles.has("Fredoka font") and ios_titles.has("Nunito font"), "iOS keeps the game, engine and font notices")
	for title: String in Licenses.IOS_FILES:
		_check(ios_titles.has(title) == FileAccess.file_exists(Licenses.IOS_FILES[title]), "iOS lists %s only when the build includes its notice" % title)
	PlatformSupport.override_platform = ""

func _native_services() -> void:
	_check(NativeBridge.singleton("secure_store") == null and not InviteShare.native_share("x"), "A build without a plugin finds none")
	var fake := FakeIOS.new()
	Engine.register_singleton(NativeBridge.IOS, fake)
	for service: String in ["secure_store", "share", "invite_link", "purchases", "notifications", "games"]:
		_check(NativeBridge.singleton(service) == fake, "The iOS plugin serves " + service)
	_check(NativeBridge.singleton("photos") == null, "Photo capture stays Android only")
	# Game Center answers through the same games interface as Play Games.
	var games := GamesProvider.new(NativeBridge.singleton("games"), "game_center", self)
	var signed: Dictionary = await games.authenticate(false)
	_check(games.kind() == "game_center" and signed.get("ok", false) and signed.get("signed_in", false) and signed.get("player_key") == "f".repeat(64), "Game Center sign-in comes back through the shared games methods")
	var refused: Dictionary = await games.server_credential("")
	_check(not refused.get("ok", true) and refused.get("code") == "failed", "A native error reaches the game only as a known code")

	var secrets := Secrets.new()
	root.add_child(secrets)
	var results: Array = []
	secrets.completed.connect(func(id: String, operation: String, payload: Dictionary): results.append([id, operation, payload]))
	_check(secrets.is_available(), "The Keychain store is available through the iOS plugin")
	var put_id: String = secrets.put_secret("device_token", "secret-value")
	_check(fake.calls.back() == ["secure_put", "device_token", "secret-value", put_id], "Secure writes reach the plugin with the request ID last")
	fake.secure_result.emit(put_id, "put", '{"stored":true}')
	_check(results == [[put_id, "put", {"stored": true}]], "The Keychain result completes the matching request")
	secrets.queue_free()

	var message := InviteShare.message("P".repeat(22))
	_check(InviteShare.native_share(message) and fake.calls.back() == ["share_text", message], "Share invite opens the iOS share sheet with the link and code")

	var links := InviteLinkBridge.new()
	var received: Array = []
	links.received.connect(func(result: Dictionary): received.append(result))
	var player := "Pp_-abcdefghijklmnopqr"
	fake.pending_link = "https://aamirazeez.com/after-you/link#friend-" + player
	root.add_child(links)
	await process_frame
	await process_frame
	_check(received.size() == 1 and received[0].get("ok") == true and received[0].get("type") == ShareCodes.FRIEND and received[0].get("id") == player, "A cold-start Universal Link is taken once and parsed")
	for link: String in ["https://aamirazeez.com/after-you/link/?c=friend-" + player, "https://aamirazeez.com/after-you/link?c=friend-aamir", "https://aamirazeez.com/after-you/link/#friend-" + player]:
		received.clear()
		fake.pending_link = link
		fake.invite_link_available.emit()
		await process_frame
		_check(received.size() == 1 and received[0].get("ok") == true, "A warm Universal Link in this form opens Add friend: " + link.get_slice("link", 1))
	received.clear()
	fake.pending_link = "invalid"
	fake.invite_link_available.emit()
	await process_frame
	_check(received.size() == 1 and received[0].get("ok") == false, "A rejected link reaches the game as one generic error")
	links.queue_free()

	var notifications := NotificationBridge.new()
	root.add_child(notifications)
	var status: Dictionary = await notifications.call_native("status")
	_check(status.get("ok") == true and status.data.get("configured") == false, "Notification requests reach the iOS plugin, which reports push unconfigured without Firebase")
	var hints := [0]
	notifications.token_changed.connect(func(): hints[0] += 1)
	fake.notification_token_changed.emit('{"generation":2,"registration_pending":false}')
	_check(hints[0] == 0, "A settled registration asks for no reconcile")
	fake.notification_token_changed.emit('{"generation":2,"registration_pending":false,"route_pending":true}')
	_check(hints[0] == 1, "A tap recorded after the resume check asks the game to read the route again")
	notifications.queue_free()

	PlatformSupport.override_platform = PlatformSupport.IOS
	var purchases := Purchases.new()
	purchases._configuration = APP_STORE.duplicate()
	root.add_child(purchases)
	_check(purchases.is_available() and purchases._native == fake, "App Store purchases use the iOS plugin")
	purchases.queue_free()
	var disabled := Purchases.new()
	disabled._configuration = GOOGLE_PLAY.duplicate()
	root.add_child(disabled)
	var errors: Array = []
	disabled.failed.connect(func(_id, _operation, code, text, _cancelled): errors.append([code, text]))
	disabled.purchase("default", "$rc_monthly")
	await process_frame
	_check(errors.size() == 1 and errors[0][0] == "store_disabled" and errors[0][1] == PlayerCopy.PURCHASES_49387E2DE82E_IOS, "A store that iOS cannot use explains itself without naming Google Play or an old free-chapter list")
	disabled.queue_free()
	PlatformSupport.override_platform = ""
	await process_frame
	Engine.unregister_singleton(NativeBridge.IOS)
	fake.free()

func _paywall_and_settings() -> void:
	var scene := App.new()
	scene.saves = Storage.new(_path("ios-paywall"))
	root.add_child(scene)
	scene.set_process(false)
	scene.set_physics_process(false)
	scene.world.set_process(false)
	scene.purchases.queue_free()
	var store := FakeStore.new()
	scene.purchases = store
	scene.add_child(store)

	# Android keeps both ways out of a build without a store.
	PlatformSupport.override_platform = PlatformSupport.ANDROID
	scene.config.merge(TESTER_ONLY, true)
	scene.store_flow.show_paywall()
	await process_frame
	_check(_button(scene, "Get it on Google Play") != null and _button(scene, "Tester code") != null, "Android without a store still offers Google Play and Tester code")

	# An iOS App Store build without a store shows neither.
	PlatformSupport.override_platform = PlatformSupport.IOS
	PlatformSupport.override_release = true
	scene.store_flow.show_paywall()
	await process_frame
	_check(_button(scene, "Get it on Google Play") == null and _button(scene, "Tester code") == null, "The iOS paywall has no Google Play link and no Tester code")
	scene.settings_flow.show_settings("account")
	await process_frame
	_check(_button(scene, "Tester code") == null and _button(scene, "Account & recovery") != null, "iOS settings hide Tester code and keep Account & recovery")
	PlatformSupport.override_release = false
	scene.settings_flow.show_settings("account")
	await process_frame
	_check(_button(scene, "Tester code") != null, "An iOS debug build keeps Tester code for testing")

	# The App Store offer: auto-renew terms, Restore, Terms of Use and App Store management.
	PlatformSupport.override_release = true
	scene.config.merge(APP_STORE, true)
	scene.store_flow.purchase_offer = {"offering_id": "offer", "packages": [
		{"price": "$0.99", "offering_id": "offer", "id": "$rc_monthly", "type": "MONTHLY", "period": "month"},
		{"price": "$9.99", "offering_id": "offer", "id": "$rc_annual", "type": "ANNUAL", "period": "year"}]}
	scene.store_flow._show_store_offer()
	await process_frame
	_check(_label(scene, PlayerCopy.SUBSCRIPTION_TERMS_APP_STORE) and not _label(scene, PlayerCopy.SUBSCRIPTION_TERMS_PLAY), "The iOS offer states the App Store renewal terms")
	_check(_button(scene, "Restore purchases") != null and _find(scene, "TermsOfUse") != null, "The iOS offer has Restore and a Terms of Use link")
	store.entitled = true
	_check(scene.store_flow._manage_subscription_available(), "An App Store subscriber can manage the subscription")
	scene.store_flow._show_full_journey_unlocked()
	await process_frame
	_check(_label(scene, PlayerCopy.SUBSCRIPTION_ACTIVE_IOS) and _button(scene, PlayerCopy.SUBSCRIPTION_MANAGE) != null, "The unlocked screen points to the App Store")
	PlatformSupport.override_platform = ""
	PlatformSupport.override_release = false
	root.remove_child(scene)
	scene.free()

func _path(label: String) -> String:
	var result := "user://test-%s-%d.json" % [label, Time.get_ticks_usec()]
	paths.append(result)
	return result

func _find(node: Node, name: String) -> Node:
	if node.name == name: return node
	for child: Node in node.get_children():
		var found := _find(child, name)
		if found != null: return found
	return null

func _button(node: Node, value: String) -> Button:
	# A Settings row or rail item reads its label out instead of showing text.
	if node is Button and (node.text == value or (node.text.is_empty() and node.accessibility_name == value)) and node.is_visible_in_tree() and not node.is_queued_for_deletion(): return node
	for child: Node in node.get_children():
		var found := _button(child, value)
		if found != null: return found
	return null

func _label(node: Node, value: String) -> bool:
	if node is Label and node.text == value and not node.is_queued_for_deletion(): return true
	for child: Node in node.get_children():
		if _label(child, value): return true
	return false

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
