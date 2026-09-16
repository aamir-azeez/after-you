extends SceneTree

const Tester = preload("res://services/tester_access.gd")
const URL := "https://tester.example.invalid"
const OWNER := "aaaaaaaaaaaaaaaaaaaaaa"
const TOKEN := "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
const OTHER := "cccccccccccccccccccccc"
const OTHER_TOKEN := "ddddddddddddddddddddddddddddddddddddddddddd"
const CODE := "SYNTHETIC-ONLY-CLIENT-CODE"
var checks := 0
var failures := 0

class Vault extends RefCounted:
	signal put_entered
	signal released
	var identity: Dictionary = {"player_id":OWNER,"device_token":TOKEN}
	var recovering := false
	var values: Dictionary = {}
	var jobs: Array = []
	var calls: Array = []
	var serial := 0
	var busy := false
	var block_put := false
	var put_failed := false
	var put_ack: Dictionary = {"stored":true}
	var remove_ack: Dictionary = {"removed":true}
	var before_put_ack: Callable
	func enqueue(node: Node, operation: String, name: String, value: String = "") -> String:
		serial += 1
		var id := "secret-%d" % serial
		jobs.append({"node":node,"id":id,"operation":operation,"name":name,"value":value})
		calls.append([operation,name])
		_pump.call_deferred()
		return id
	func _pump() -> void:
		if busy: return
		busy = true
		while not jobs.is_empty():
			var job: Dictionary = jobs.pop_front()
			var payload := {}
			if job.operation == "put":
				put_entered.emit.call_deferred()
				if block_put: await released
				if not put_failed: values[job.name] = job.value
				payload = put_ack.duplicate(true)
				if before_put_ack.is_valid(): before_put_ack.call()
			elif job.operation == "remove":
				if remove_ack == {"removed":true}: values.erase(job.name)
				payload = remove_ack.duplicate(true)
			else:
				if job.name == "player_identity": payload = {"found":true,"value":JSON.stringify(identity)}
				elif job.name == "recovery_pending": payload = {"found":recovering,"value":"pending" if recovering else null}
				else: payload = {"found":values.has(job.name),"value":values.get(job.name)}
			if is_instance_valid(job.node):
				if job.operation == "put" and put_failed: job.node.failed.emit(job.id, job.operation, "synthetic_write_failed")
				else: job.node.completed.emit(job.id,job.operation,payload)
		busy = false

class SecretPort extends Node:
	signal completed(id: String, operation: String, payload: Dictionary)
	signal failed(id: String, operation: String, code: String)
	var vault: Vault
	func get_secret(name: String) -> String: return vault.enqueue(self,"get",name)
	func put_secret(name: String, value: String) -> String: return vault.enqueue(self,"put",name,value)
	func remove_secret(name: String) -> String: return vault.enqueue(self,"remove",name)

class Wire extends RefCounted:
	signal entered
	signal released
	var block := false
	var calls: Array = []
	var response: Dictionary = {}

class Api extends Node:
	var base_url := ""
	var player_id := ""
	var device_token := ""
	var wire: Wire
	func request_json(method: int, path: String, body: Dictionary = {}) -> Dictionary:
		# Only synthetic in-memory fixtures contain the body; nothing is printed.
		wire.calls.append([method,path,body.duplicate(true),base_url,player_id,device_token])
		wire.entered.emit.call_deferred()
		if wire.block: await wire.released
		var parser := JSON.new()
		parser.parse(JSON.stringify(wire.response))
		return parser.data

func _initialize() -> void: _run.call_deferred()

func _grant(owner: String = OWNER) -> Dictionary:
	return {"schema_version":1,"granted":true,"access_source":"tester_grant","entitlement":"full_journey","player_id":owner,"granted_at":"2026-09-16T10:00:00.123Z"}

func _fixture(vault: Vault = null) -> Dictionary:
	var storage := Vault.new() if vault == null else vault
	var wire := Wire.new()
	wire.response = {"ok":true,"status":200,"data":_grant()}
	var service := Tester.new()
	service.secret_factory = func():
		var port := SecretPort.new()
		port.vault = storage
		return port
	service.api_factory = func():
		var api := Api.new()
		api.wire = wire
		return api
	root.add_child(service)
	return {"service":service,"vault":storage,"wire":wire}

func _envelope(owner: String = OWNER, token: String = TOKEN, url: String = URL) -> Dictionary:
	return {"schema_version":1,"authority":url,"player_id":owner,"credential_hash":token.sha256_text(),"receipt":_grant(owner)}

func _capture(service: Node, result: Dictionary, operation: String = "restore", owner: String = OWNER) -> void:
	result.done = false
	if operation == "restore":
		result.value = await service.restore(URL,owner)
	else:
		result.value = await service.load_cached(URL,owner)
	result.done = true

func _until(predicate: Callable, label: String) -> bool:
	var deadline := Time.get_ticks_msec() + 2000
	while not predicate.call() and Time.get_ticks_msec() < deadline: await process_frame
	var passed: bool = predicate.call()
	_check(passed,label)
	return passed

func _run() -> void:
	await _cache()
	await _network_and_persistence()
	await _strict_receipts()
	await _late_network()
	await _late_put()
	await _explicit_erasure()
	await process_frame
	print("Tester access: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _cache() -> void:
	var f := _fixture()
	var miss: Dictionary = await f.service.load_cached(URL,OWNER)
	_check(miss == {"ok":true,"granted":false,"durable":true},"Cold miss is a successful local load")
	_check(f.service.cache_loaded_for(URL,OWNER,TOKEN) and not f.service.active(URL,OWNER,TOKEN),"Loaded miss is bound but inactive")
	_check(f.wire.calls.is_empty(),"Startup cache load never makes HTTP")
	var name: String = Tester._scope(URL,OWNER,TOKEN)
	_check(name.length() <= 64 and name != Tester._scope(URL,OTHER,TOKEN) and name != Tester._scope(URL,OWNER,OTHER_TOKEN) and name != Tester._scope("https://other.invalid",OWNER,TOKEN),"Cache keys separate origin owner and credential")
	f.vault.values[name] = JSON.stringify(_envelope())
	var loaded: Dictionary = await f.service.load_cached("https://TESTER.example.invalid:443/",OWNER)
	_check(loaded.ok and loaded.granted and loaded.durable,"Strict durable receipt loads without HTTP")
	_check(f.service.active(URL,OWNER,TOKEN) and not f.service.active(URL,OTHER,TOKEN) and not f.service.active(URL,OWNER,OTHER_TOKEN),"Active admission requires exact binding")
	f.service.free()
	var cold := _fixture(f.vault)
	_check((await cold.service.load_cached(URL)).granted,"Cold service recovers cache from secure current identity")
	_check(cold.wire.calls.is_empty(),"Second process-style load is still local only")
	for variant in ["json","schema","owner","hash","receipt","oversize"]:
		var bad: Dictionary = _envelope()
		match variant:
			"schema": bad.schema_version = 2
			"owner": bad.player_id = OTHER
			"hash": bad.credential_hash = "f".repeat(64)
			"receipt": bad.receipt.access_source = "play_purchase"
		cold.vault.values[name] = "{" if variant == "json" else "x".repeat(4097) if variant == "oversize" else JSON.stringify(bad)
		cold.service.invalidate()
		var rejected: Dictionary = await cold.service.load_cached(URL,OWNER)
		_check(not rejected.ok and not cold.service.active(URL,OWNER,TOKEN),"Malformed %s cached receipt cannot grant" % variant)
	cold.service.free()

func _network_and_persistence() -> void:
	var f := _fixture()
	var redeemed: Dictionary = await f.service.redeem(URL,OWNER,CODE)
	_check(redeemed == {"ok":true,"granted":true,"durable":true},"Redeem becomes active only after durable acknowledgment")
	_check(f.wire.calls.size() == 1 and f.wire.calls[0] == [HTTPClient.METHOD_POST,"/v1/tester-access",{"schema_version":1,"code":CODE},URL,OWNER,TOKEN],"Redeem issues one exact authenticated POST")
	_check(not JSON.stringify(f.vault.values).contains(CODE) and not JSON.stringify(f.vault.values).contains(TOKEN),"Cache contains neither submitted code nor raw device credential")
	var receipt_before: String = f.vault.values[Tester._scope(URL,OWNER,TOKEN)]
	f.wire.response = {"ok":false,"status":503,"code":"service_unavailable"}
	var interrupted: Dictionary = await f.service.restore(URL,OWNER)
	_check(not interrupted.ok and interrupted.granted and interrupted.durable and f.service.active(URL,OWNER,TOKEN),"Optional network error does not revoke a valid permanent cache")
	_check(f.vault.values[Tester._scope(URL,OWNER,TOKEN)] == receipt_before,"Network failure leaves durable receipt unchanged")
	f.wire.response = {"ok":true,"status":200,"data":_grant()}
	f.service.invalidate()
	var restored: Dictionary = await f.service.restore(URL,OWNER)
	_check(restored.ok and restored.granted and f.wire.calls[-1][0] == HTTPClient.METHOD_GET and f.wire.calls[-1][2] == {},"Explicit restore uses no code after new redemptions are disabled")
	f.wire.response = {"ok":true,"status":200,"data":{"schema_version":1,"granted":false,"player_id":OWNER}}
	var mismatch: Dictionary = await f.service.restore(URL,OWNER)
	_check(not mismatch.ok and mismatch.granted and f.service.active(URL,OWNER,TOKEN),"Unexpected absent server grant cannot silently revoke permanent local grant")
	f.service.free()
	for variant in ["failed","bad_ack","extra_ack"]:
		var bad := _fixture()
		bad.vault.put_failed = variant == "failed"
		bad.vault.put_ack = {"stored":1} if variant == "bad_ack" else {"stored":true,"extra":true} if variant == "extra_ack" else {"stored":true}
		var denied: Dictionary = await bad.service.restore(URL,OWNER)
		await process_frame
		_check(not denied.ok and not bad.service.active(URL,OWNER,TOKEN),"Unconfirmed %s write never activates grant" % variant)
		_check(bad.vault.values.is_empty(),"Unconfirmed %s write is queued for exact-scope removal" % variant)
		bad.service.free()

func _strict_receipts() -> void:
	for variant in ["owner","source","entitlement","date","schema","bool","extra","missing"]:
		var f := _fixture()
		match variant:
			"owner": f.wire.response.data.player_id = OTHER
			"source": f.wire.response.data.access_source = "review_grant"
			"entitlement": f.wire.response.data.entitlement = "full_journey_play"
			"date": f.wire.response.data.granted_at = "2026-02-30T10:00:00.123Z"
			"schema": f.wire.response.data.schema_version = true
			"bool": f.wire.response.data.granted = 1
			"extra": f.wire.response.data.extra = true
			"missing": f.wire.response.data.erase("granted_at")
		var denied: Dictionary = await f.service.restore(URL,OWNER)
		_check(not denied.ok and not f.service.active(URL,OWNER,TOKEN) and f.vault.values.is_empty(),"Strict %s response cannot become durable access" % variant)
		f.service.free()
	var none := _fixture()
	none.wire.response.data = {"schema_version":1,"granted":false,"player_id":OWNER}
	_check(await none.service.restore(URL,OWNER) == {"ok":true,"granted":false,"durable":true},"Authenticated no-grant response remains ordinary absence")
	none.service.free()
	for url in ["http://tester.example.invalid","https://user@tester.example.invalid","https://tester.example.invalid/path","https://tester.example.invalid?x=1"]:
		var invalid := _fixture()
		_check(not (await invalid.service.restore(url,OWNER)).ok and invalid.wire.calls.is_empty(),"Unsafe or ambiguous authority is refused before HTTP")
		invalid.service.free()

func _late_network() -> void:
	for variant in ["owner","credential","recovery","cancel"]:
		var f := _fixture()
		f.wire.block = true
		var result := {}
		_capture(f.service,result)
		if not await _until(func(): return not f.wire.calls.is_empty(),"Deferred HTTP entered"):
			f.wire.released.emit()
			f.service.free()
			continue
		match variant:
			"owner": f.vault.identity.player_id = OTHER
			"credential": f.vault.identity.device_token = OTHER_TOKEN
			"recovery": f.vault.recovering = true
			"cancel": f.service.invalidate()
		f.wire.released.emit()
		await _until(func(): return result.get("done",false),"Deferred HTTP settles")
		_check(not result.get("value",{}).get("ok",false) and not f.service.active(URL,OWNER,TOKEN) and f.vault.values.is_empty(),"Late %s HTTP cannot cache old grant" % variant)
		f.service.free()

func _late_put() -> void:
	var f := _fixture()
	f.vault.block_put = true
	var result := {}
	_capture(f.service,result)
	await _until(func(): return f.vault.calls.any(func(c): return c[0] == "put"),"Delayed durable put entered")
	_check(not f.service.active(URL,OWNER,TOKEN),"Server success alone cannot activate before native write ACK")
	f.service.invalidate()
	f.vault.identity = {"player_id":OTHER,"device_token":OTHER_TOKEN}
	var newer := _fixture(f.vault)
	newer.wire.response.data = _grant(OTHER)
	var next := {}
	_capture(newer.service,next,"restore",OTHER)
	f.vault.block_put = false
	f.vault.released.emit()
	await _until(func(): return result.get("done",false) and next.get("done",false),"Old and new bindings settle after FIFO release")
	_check(not result.get("value",{}).get("ok",false) and next.get("value",{}).get("ok",false),"Cancelled old write cannot grant while new owner succeeds")
	_check(not f.vault.values.has(Tester._scope(URL,OWNER,TOKEN)) and f.vault.values.has(Tester._scope(URL,OTHER,OTHER_TOKEN)),"FIFO old-scope cleanup cannot remove new binding")
	_check(newer.service.active(URL,OTHER,OTHER_TOKEN),"New owner admission survives old callback cleanup")
	f.service.free()
	newer.service.free()
	var changed := _fixture()
	var vault: Vault = changed.vault
	vault.before_put_ack = func(): vault.identity.device_token = OTHER_TOKEN
	var rejected: Dictionary = await changed.service.restore(URL,OWNER)
	await process_frame
	_check(not rejected.ok and changed.vault.values.is_empty() and not changed.service.active(URL,OWNER,TOKEN),"Credential change after native write is rechecked and cleaned")
	vault.before_put_ack = Callable()
	changed.service.free()

func _explicit_erasure() -> void:
	var f := _fixture()
	_check((await f.service.restore(URL,OWNER)).granted,"Fixture owns a durable grant before deletion cleanup")
	var other_name: String = Tester._scope(URL,OTHER,OTHER_TOKEN)
	f.vault.values[other_name] = JSON.stringify(_envelope(OTHER,OTHER_TOKEN))
	f.vault.identity = {}
	var erased: Dictionary = await f.service.erase_binding(URL,OWNER,TOKEN)
	_check(erased == {"ok":true,"granted":false,"durable":true},"Explicit erasure works after server identity deletion")
	_check(not f.vault.values.has(Tester._scope(URL,OWNER,TOKEN)) and f.vault.values.has(other_name),"Erasure removes only the named owner/credential scope")
	_check(not f.service.active(URL,OWNER,TOKEN),"Explicit erasure invalidates memory admission")
	f.vault.remove_ack = {"removed":false}
	_check(not (await f.service.erase_binding(URL,OTHER,OTHER_TOKEN)).ok,"Unacknowledged removal is retryable failure")
	f.service.free()

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
