extends SceneTree

const Purchases = preload("res://services/purchases.gd")
const Secrets = preload("res://services/secure_store.gd")
var failures: Array[String] = []
var purchase_errors: Array = []
var secret_errors: Array = []

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
	if failures.is_empty():
		print("PASS: native wrapper unavailable/error/schema/revocation checks")
	else:
		for failure in failures:
			push_error(failure)
	quit(0 if failures.is_empty() else 1)
