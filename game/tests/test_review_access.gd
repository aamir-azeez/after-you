extends SceneTree

const Review = preload("res://services/review_access.gd")
const Purchases = preload("res://services/purchases.gd")
const OWNER := "aaaaaaaaaaaaaaaaaaaaaa"
const TOKEN := "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
var checks := 0
var failures := 0

class SecretReader extends Node:
	signal completed(id: String, operation: String, payload: Dictionary)
	signal failed(id: String, operation: String, code: String)
	var player_owner := OWNER
	var token := TOKEN
	var recovering := false
	var calls: Array[String] = []
	func get_secret(name: String) -> String:
		calls.append(name)
		var id := "secret-%d" % calls.size()
		var value := {"found": false, "value": null}
		if name == "player_identity": value = {"found": true, "value": JSON.stringify({"player_id":player_owner,"device_token":token})}
		elif recovering: value = {"found":true,"value":"saved recovery"}
		completed.emit.call_deferred(id, "get", value)
		return id

class ReadApi extends Node:
	signal entered
	signal released
	var base_url := ""
	var player_id := ""
	var device_token := ""
	var delayed := false
	var response: Dictionary = {}
	var calls: Array = []
	func request_json(method: int, path: String, body: Dictionary = {}) -> Dictionary:
		calls.append([method,path,body,player_id,device_token])
		entered.emit.call_deferred()
		if delayed: await released
		return response.duplicate(true)

class ReviewStub extends Node:
	signal entered
	signal released
	var allowed := true
	var delayed := false
	var invalidations := 0
	func invalidate() -> void: invalidations += 1
	func verify(_owner: String, _url: String) -> bool:
		entered.emit.call_deferred()
		if delayed: await released
		return allowed

func _initialize() -> void: _run.call_deferred()

func _positive() -> Dictionary:
	return {"ok":true,"status":200,"data":{"full_journey":true,"status":"verified","environment":"production","checked_at":"2026-09-16T00:00:00.000Z","access_source":"review_grant","entitlement":"full_journey_play","player_id":OWNER}}

func _fixture(delayed: bool = false) -> Dictionary:
	var secret := SecretReader.new()
	var api := ReadApi.new()
	api.response = _positive()
	api.delayed = delayed
	var service := Review.new()
	service.secret_factory = func(): return secret
	service.api_factory = func(): return api
	root.add_child(service)
	return {"service":service,"api":api,"secret":secret,"calls":api.calls}

func _capture(service: Node, result: Dictionary) -> void:
	result.done = false
	result.value = await service.verify(OWNER, "https://example.invalid")
	result.done = true

func _run() -> void:
	var good := _fixture()
	_check(await good.service.verify(OWNER,"https://example.invalid"), "Fresh authenticated grant with unchanged identity succeeds")
	_check(good.secret.calls == ["recovery_pending","player_identity","recovery_pending","player_identity"], "Existing identity and recovery state are re-read after server await")
	# The test transport records credentials only in this synthetic in-memory fixture.
	_check(good.calls == [[HTTPClient.METHOD_GET,"/v1/entitlement",{},OWNER,TOKEN]], "Verification is one authenticated GET with no write body")
	good.service.free()
	for mutation in ["owner","credential","recovery","cancel","source"]:
		var fixture := _fixture(true)
		var result := {}
		_capture(fixture.service,result)
		await fixture.api.entered
		match mutation:
			"owner": fixture.secret.player_owner = "c".repeat(22)
			"credential": fixture.secret.token = "d".repeat(43)
			"recovery": fixture.secret.recovering = true
			"cancel": fixture.service.invalidate()
			"source": fixture.api.response.data.access_source = "play_purchase"
		fixture.api.released.emit()
		while not result.done: await process_frame
		_check(not result.value, "Changed %s during await cannot grant review access" % mutation)
		fixture.service.free()
	for field in ["player_id","access_source","entitlement","status","full_journey"]:
		var response := _positive()
		response.data[field] = "unexpected"
		_check(not Review.valid_response(response,OWNER), "Malformed or unrelated %s rejected" % field)
	for status in [0,401,403,404,500]:
		var response := _positive()
		response.status = status
		_check(not Review.valid_response(response,OWNER), "Read rejection never grants access")
	var service := Purchases.new()
	service._configuration = {"purchase_mode":"google_play","entitlement_id":"full_journey_play","api_base_url":"https://example.invalid"}
	var stub := ReviewStub.new()
	service.review_access_factory = func(): return stub
	root.add_child(service)
	var promo := {"schema_version":1,"mode":"google_play","player_id":OWNER,"entitlements":{"full_journey_play":{"active":true,"store":"PROMOTIONAL"}}}
	service.customer_info = promo.duplicate(true)
	_check(not service.has_entitlement(), "SDK promotional grant alone never unlocks")
	service._pending["review"] = "get_customer_info"
	await service._on_result("review","get_customer_info",JSON.stringify(promo))
	_check(service.has_entitlement(), "Explicit SDK result plus successful server verifier admits review")
	service._notification(NOTIFICATION_APPLICATION_PAUSED)
	_check(not service.has_entitlement(), "Backgrounding removes ephemeral review access")
	service._notification(NOTIFICATION_APPLICATION_RESUMED)
	_check(not service.has_entitlement(), "Resume alone cannot restore review access")
	stub.allowed = false
	service._pending["denied"] = "get_customer_info"
	await service._on_result("denied","get_customer_info",JSON.stringify(promo))
	_check(not service.has_entitlement(), "Denied server check cannot reuse earlier admission")
	service.free()
	for reason in ["background", "source_changed"]:
		var delayed_service := Purchases.new()
		delayed_service._configuration = {"purchase_mode":"google_play","entitlement_id":"full_journey_play","api_base_url":"https://example.invalid"}
		var delayed_stub := ReviewStub.new()
		delayed_stub.delayed = true
		delayed_service.review_access_factory = func(): return delayed_stub
		root.add_child(delayed_service)
		delayed_service._pending["late"] = "get_customer_info"
		delayed_service._on_result("late","get_customer_info",JSON.stringify(promo))
		await delayed_stub.entered
		if reason == "background": delayed_service._notification(NOTIFICATION_APPLICATION_PAUSED)
		else: delayed_service._on_customer_info(JSON.stringify({"schema_version":1,"mode":"google_play","entitlements":{}}))
		delayed_stub.released.emit()
		await process_frame
		_check(not delayed_service.has_entitlement(), "Late review result after %s cannot grant" % reason)
		delayed_service.free()
	print("Review access: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
