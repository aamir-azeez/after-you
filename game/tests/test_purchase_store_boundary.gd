extends SceneTree

const Purchases = preload("res://services/purchases.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	var play := {"purchase_mode":"google_play", "entitlement_id":"full_journey_play"}
	var demo := {"purchase_mode":"test_store", "entitlement_id":"full_journey"}
	var payload := {"schema_version":1,"mode":"google_play","entitlements":{
		"full_journey":{"active":true,"store":"TEST_STORE"},
		"full_journey_play":{"active":true,"store":"PLAY_STORE","sandbox":false}}}
	_check(Purchases.entitled_for_configuration(payload, play), "Actual Play store entitlement is eligible")
	payload.entitlements.full_journey_play.sandbox = true
	_check(Purchases.entitled_for_configuration(payload, play), "Play license test stays a Play store purchase")
	for store in ["TEST_STORE", "PROMOTIONAL", "UNKNOWN_STORE", "APP_STORE", ""]:
		payload.entitlements.full_journey_play.store = store
		_check(not Purchases.entitled_for_configuration(payload, play), "Other store cannot unlock Play")
	payload.entitlements.full_journey_play.store = "PLAY_STORE"
	payload.mode = "test_store"
	_check(not Purchases.entitled_for_configuration(payload, play), "Wrong configured native mode cannot unlock")
	payload.mode = "google_play"
	payload.entitlements.erase("full_journey_play")
	_check(not Purchases.entitled_for_configuration(payload, play), "Existing demo buyer cannot unlock Play")
	_check(Purchases.entitled_for_configuration(payload, demo), "Existing demo entitlement remains supported")
	_check(not Purchases.entitled_for_configuration(payload, {"purchase_mode":"google_play","entitlement_id":"full_journey"}), "Misconfigured Play entitlement fails closed")
	_check(not Purchases.entitled_for_configuration(payload, {}), "Missing configuration fails closed")
	var service := Purchases.new()
	service._configuration = play
	service.customer_info = payload
	_check(not service.has_entitlement("full_journey"), "Explicit old entitlement cannot bypass store boundary")
	service.free()
	print("Purchase store boundary: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
