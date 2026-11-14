extends SceneTree

const Purchases = preload("res://services/purchases.gd")
const Secrets = preload("res://services/secure_store.gd")
const FileShare = preload("res://services/file_share.gd")
var failures: Array[String] = []
var purchase_errors: Array = []
var secret_errors: Array = []
var secret_results: Array = []

class SyntheticClipboardNative extends RefCounted:
	var copied_arguments: Array = []
	func secure_copy_recovery(player_id: String, recovery_code: String, request_id: String) -> void:
		copied_arguments = [player_id, recovery_code, request_id]

class SyntheticGuardNative extends RefCounted:
	var calls: Array = []
	func secure_confirm_device(request_id: String) -> void:
		calls.append(["confirm", request_id])
	func secure_private_screen(on: bool) -> void:
		calls.append(["private", on])
	func secure_clear_recovery_clip(recovery_code: String) -> void:
		calls.append(["clear", recovery_code])

func _init() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _run() -> void:
	var purchases = Purchases.new()
	# Explicit Play fixture keeps the native-absence test separate from tester-only gating.
	purchases._configuration = {"purchase_mode":"google_play", "revenuecat_public_key":"goog_synthetic_public_key", "entitlement_id":"full_journey_play"}
	var secrets = Secrets.new()
	root.add_child(purchases)
	root.add_child(secrets)
	purchases.failed.connect(func(id, op, code, message, cancelled): purchase_errors.append([id, op, code, message, cancelled]))
	secrets.failed.connect(func(id, op, code): secret_errors.append([id, op, code]))
	secrets.completed.connect(func(id, op, payload): secret_results.append([id, op, payload]))
	check(not purchases.has_entitlement(), "An empty service must not grant premium.")
	if not Engine.has_singleton("AfterYouAndroid"):
		var purchase_id = purchases.purchase("default", "$rc_lifetime")
		var secret_id = secrets.get_secret("device_token")
		await process_frame
		check(purchase_errors.size() == 1, "Unavailable purchases must report exactly one error.")
		check(secret_errors.size() == 1, "Unavailable Keystore must report exactly one error.")
		if not purchase_errors.is_empty():
			check(purchase_errors[0][0] == purchase_id and purchase_errors[0][2] == "android_required", "Purchase error must match the request.")
		if not secret_errors.is_empty():
			check(secret_errors[0][0] == secret_id, "Storage error must match the request.")
		check(not purchases.has_entitlement(), "An unavailable native store cannot unlock premium.")
	# Synthetic native payloads validate only the facade, never store integration.
	var play_payload: Dictionary = {"schema_version":1, "mode":"google_play", "entitlements":{"full_journey_play":{"active":true, "store":"PLAY_STORE", "product_id":"after_you_full_journey"}}}
	purchases._pending["synthetic"] = "configure"
	purchases._on_result("synthetic", "configure", '{"schema_version":1,"entitlements":{"full_journey":{"active":false}}}')
	check(not purchases.has_entitlement(), "Inactive entitlement must remain inactive.")
	purchases._on_customer_info('{"schema_version":1,"mode":"test_store","entitlements":{"full_journey":{"active":true}}}')
	check(not purchases.has_entitlement(), "Retained Test Store payload cannot unlock Play.")
	purchases._on_customer_info(JSON.stringify(play_payload))
	check(purchases.has_entitlement(), "Exact active Google Play product must reach the presentation cache.")
	play_payload.entitlements.full_journey_play.active = false
	purchases._on_customer_info(JSON.stringify(play_payload))
	check(not purchases.has_entitlement(), "Revocation must clear the presentation cache.")
	purchases._pending["bad_schema"] = "get_customer_info"
	purchases._on_result("bad_schema", "get_customer_info", '{"schema_version":99,"entitlements":{"full_journey":{"active":true}}}')
	check(not purchases.has_entitlement(), "An unsupported schema cannot grant access.")
	# A tester-only build ignores even a previously received valid SDK receipt.
	purchases._configuration = {"purchase_mode":"tester_only", "revenuecat_public_key":"", "entitlement_id":"full_journey"}
	play_payload.entitlements.full_journey_play.active = true
	purchases._on_customer_info(JSON.stringify(play_payload))
	check(not purchases.has_entitlement(), "Tester-only mode cannot consume stale Play or Test Store SDK access.")
	var clipboard_native := SyntheticClipboardNative.new()
	secrets._native = clipboard_native
	var copy_id: String = secrets.copy_recovery("i".repeat(22), "r".repeat(43))
	check(clipboard_native.copied_arguments == ["i".repeat(22), "r".repeat(43), copy_id], "The clipboard wrapper must forward only the identity, recovery code and request ID.")
	secrets._on_result(copy_id, "copy_recovery", '{"copied":true}')
	check(secret_results.size() == 1 and secret_results[0] == [copy_id, "copy_recovery", {"copied":true}], "The clipboard acknowledgement must correlate to its original request without secret payloads.")
	secrets._on_result(copy_id, "copy_recovery", '{"copied":true}')
	check(secret_results.size() == 1, "A repeated clipboard acknowledgement must not create another result.")
	check(not secrets._deadlines.has(copy_id), "A successful request must remove its timeout deadline.")
	var errors_before: int = secret_errors.size()
	var unanswered_copy: String = secrets.copy_recovery("i".repeat(22), "r".repeat(43))
	check(secret_errors.size() == errors_before, "A native request must have time to return before reporting a timeout.")
	check(Secrets.REQUEST_TIMEOUT_MS == 9000, "Native requests must expire before the application ten-second wait.")
	secrets._deadlines[unanswered_copy] = Time.get_ticks_msec() - 1
	secrets._process(0.0)
	check(secret_errors.size() == errors_before + 1, "An unanswered native request must report one timeout.")
	if secret_errors.size() == errors_before + 1:
		check(secret_errors[-1] == [unanswered_copy, "copy_recovery", "native_request_timeout"], "Timeouts must identify their request without secret values.")
	check(not secrets._pending.has(unanswered_copy) and not secrets._deadlines.has(unanswered_copy), "Timeout must clean both request maps.")
	secrets._on_result(unanswered_copy, "copy_recovery", '{"copied":true}')
	secrets._on_error(unanswered_copy, "copy_recovery", "clipboard_unavailable")
	secrets._process(0.0)
	check(secret_results.size() == 1 and secret_errors.size() == errors_before + 1, "Late or duplicate native callbacks must not resurrect an expired request.")
	# The recovery code's guards: a plugin without them (iOS for now) is asked nothing.
	check(not secrets.device_check_supported(), "A plugin without the screen lock check reports none.")
	secrets.set_private_screen(true)
	secrets.clear_recovery_clip("r".repeat(43))
	var guard_native := SyntheticGuardNative.new()
	secrets._native = guard_native
	check(secrets.device_check_supported(), "A plugin with the screen lock check reports it.")
	var confirm_id: String = secrets.confirm_device()
	check(guard_native.calls == [["confirm", confirm_id]], "The screen lock check forwards only its request ID.")
	check(int(secrets._deadlines.get(confirm_id, 0)) >= Time.get_ticks_msec() + Secrets.CONFIRM_TIMEOUT_MS - 1000 and Secrets.CONFIRM_TIMEOUT_MS >= 120000, "The screen lock check waits for the player, not the nine second limit.")
	secrets.set_private_screen(true)
	secrets.clear_recovery_clip("r".repeat(43))
	check(guard_native.calls.slice(1) == [["private", true], ["clear", "r".repeat(43)]], "The private screen and clipboard calls reach the plugin unchanged.")
	# Export this run: without a plugin there is no file sheet, and nothing is written.
	if not Engine.has_singleton("AfterYouAndroid") and not Engine.has_singleton("AfterYouIOS"):
		check(not FileShare.share_file(PackedByteArray([1, 2, 3]), "relay-isles-attempt-1.afteryou"), "An unavailable share sheet must report that no file was offered.")
	check(not FileShare.share_file(PackedByteArray(), "relay-isles-attempt-1.afteryou"), "An empty file must never reach the plugin.")
	check(not FileShare.share_file(PackedByteArray([1]), "../outside.afteryou"), "A file name the plugin would change must never reach it.")
	if failures.is_empty():
		print("PASS: native wrapper unavailable/error/schema/revocation checks")
	else:
		for failure in failures:
			push_error(failure)
	quit(0 if failures.is_empty() else 1)
