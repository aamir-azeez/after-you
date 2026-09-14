extends SceneTree

const Purchases = preload("res://services/purchases.gd")
const Secrets = preload("res://services/secure_store.gd")
var failures: Array[String] = []
var purchase_errors: Array = []
var secret_errors: Array = []
var secret_results: Array = []

class SyntheticClipboardNative extends RefCounted:
	var copied_arguments: Array = []
	func secure_copy_recovery(player_id: String, recovery_code: String, request_id: String) -> void:
		copied_arguments = [player_id, recovery_code, request_id]

func _init() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _run() -> void:
	var purchases = Purchases.new()
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
	purchases._pending["synthetic"] = "configure"
	purchases._on_result("synthetic", "configure", '{"schema_version":1,"entitlements":{"full_journey":{"active":false}}}')
	check(not purchases.has_entitlement(), "Inactive entitlement must remain inactive.")
	purchases._on_customer_info('{"schema_version":1,"entitlements":{"full_journey":{"active":true}}}')
	check(purchases.has_entitlement(), "Active SDK-shaped update must reach the presentation cache.")
	purchases._on_customer_info('{"schema_version":1,"entitlements":{"full_journey":{"active":false}}}')
	check(not purchases.has_entitlement(), "Revocation must clear the presentation cache.")
	purchases._pending["bad_schema"] = "get_customer_info"
	purchases._on_result("bad_schema", "get_customer_info", '{"schema_version":99,"entitlements":{"full_journey":{"active":true}}}')
	check(not purchases.has_entitlement(), "An unsupported schema cannot grant access.")
	# Older installed plugin versions must fail this optional action without an invalid native call.
	secrets._native = RefCounted.new()
	var errors_before: int = secret_errors.size()
	var unavailable_copy: String = secrets.copy_recovery("i".repeat(22), "r".repeat(43))
	check(secret_errors.size() == errors_before, "Unavailable clipboard errors must be deferred until the caller has the request ID.")
	await process_frame
	check(secret_errors.size() == errors_before + 1, "A missing native clipboard method must report exactly one error.")
	if secret_errors.size() == errors_before + 1:
		check(secret_errors[-1] == [unavailable_copy, "copy_recovery", "native_operation_unavailable"], "A missing clipboard method must report the matching request and bounded code.")
	var clipboard_native := SyntheticClipboardNative.new()
	secrets._native = clipboard_native
	var copy_id: String = secrets.copy_recovery("i".repeat(22), "r".repeat(43))
	check(clipboard_native.copied_arguments == ["i".repeat(22), "r".repeat(43), copy_id], "The clipboard wrapper must forward only the identity, recovery code and request ID.")
	secrets._on_result(copy_id, "copy_recovery", '{"copied":true}')
	check(secret_results.size() == 1 and secret_results[0] == [copy_id, "copy_recovery", {"copied":true}], "The clipboard acknowledgement must correlate to its original request without secret payloads.")
	secrets._on_result(copy_id, "copy_recovery", '{"copied":true}')
	check(secret_results.size() == 1, "A repeated clipboard acknowledgement must not create another result.")
	if failures.is_empty():
		print("PASS: native wrapper unavailable/error/schema/revocation checks")
	else:
		for failure in failures:
			push_error(failure)
	quit(0 if failures.is_empty() else 1)
