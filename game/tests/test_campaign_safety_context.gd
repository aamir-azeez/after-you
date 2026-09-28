extends "res://tests/test_safety_client.gd"
## Real safety journal/receipt validation with finite target-scoped dispatch.
class Target extends RefCounted:
	var factory: RefCounted
	var room := ""
	func current() -> bool: return factory.current()
	func request(value: Dictionary) -> Dictionary:
		factory.scoped_calls.append(value.duplicate(true))
		if not current() or factory.refuse or value.get("body",{}).get("room_id") != room:
			return {"ok":false,"ignored":true,"code":"campaign_context_changed"}
		var result: Dictionary = await factory.api.request_json(value.method,value.path,value.body)
		return result if current() else {"ok":false,"ignored":true,"code":"campaign_context_changed"}

class Factory extends RefCounted:
	var api: Node
	var retired := false
	var refuse := false
	var null_next := false
	var requested: Array = []
	var scoped_calls: Array = []
	var contexts: Array[WeakRef] = []
	func current() -> bool: return not retired
	func for_room(room: String, purpose: String) -> RefCounted:
		requested.append({"room":room,"purpose":purpose})
		if null_next: null_next = false; return null
		var target := Target.new()
		target.factory = self
		target.room = room
		contexts.append(weakref(target))
		return target

func _case() -> Dictionary:
	var identity := Identity.new()
	var api := Server.new()
	root.add_child(api)
	var store := Store.new("user://campaign-safety-"+str(Time.get_ticks_usec()))
	var factory := Factory.new()
	factory.api = api
	var client := Client.new(api,identity.current,store,Callable(),factory)
	return {"identity":identity,"api":api,"store":store,"factory":factory,"client":client}

func _run() -> void:
	await _scoped_report_and_account_recovery()
	await _failed_factory()
	await _retirement()
	print("Campaign safety contexts: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)

func _scoped_report_and_account_recovery() -> void:
	var c := _case()
	check(await c.client.block(TARGET) and not c.client.partner_allowed("relay",ROOM,PEER),"Room-bound block uses the explicit chapter context and retains local suppression")
	check(c.factory.requested == [{"room":ROOM,"purpose":"safety"}],"Safety uses the existing relay family and explicit room instead of current gameplay selection")
	c.api.drop = true
	check(not await c.client.report(TARGET,"privacy") and not c.client.pending_report().is_empty(),"An already blocked peer can still be reported; lost accepted reply remains durable")
	var pending: Dictionary = c.client.pending_report()
	check(Canonical.same(c.factory.scoped_calls.back().body,pending),"Scoped report dispatch preserves the saved key and complete original body")
	var calls: int = c.factory.requested.size()
	c.factory.refuse = true # Room deleted/unknown; accepted account receipt remains available.
	check(await c.client.check_report() and c.client.pending_report().is_empty(),"Accepted report receipt can settle after its room authority becomes unavailable")
	check(c.factory.requested.size() == calls and c.api.calls.back().path == "/v1/safety/reports/"+str(pending.idempotency_key),"Accepted report GET bypasses failed room lookup and never repeats POST")
	check(await c.client.check_terms() and await c.client.refresh_blocks() and await c.client.unblock(PEER),"Terms, block-list and unblock stay ordinary account operations")
	check(c.factory.requested.size() == calls,"Account safety actions do not construct room contexts")
	await _dispose(c)

func _failed_factory() -> void:
	var c := _case()
	c.factory.null_next = true
	check(not await c.client.block(TARGET) and c.api.calls.is_empty(),"A supplied factory returning null never falls back to raw chapter block")
	c.factory.refuse = true
	check(not await c.client.report(TARGET,"other") and not c.client.pending_report().is_empty() and c.api.calls.is_empty(),"Held report retains original durable intent without unmarked dispatch")
	var pending: Dictionary = c.client.pending_report()
	check(not await c.client.retry_report() and Canonical.same(pending,c.client.pending_report()),"Held retry neither substitutes a room nor rewrites its request")
	c.factory.retired = true
	check(await c.client.check_terms(),"Account discovery remains usable independently of a retired room factory")
	await _dispose(c)

func _retirement() -> void:
	var c := _case()
	c.api.hold_path = "/v1/safety/report"
	var result := {"done":false,"okay":true}
	_report(c.client,result)
	check(c.api.waiting and not c.client.pending_report().is_empty(),"Real report request is suspended after its exact body is durable")
	var pending: Dictionary = c.client.pending_report()
	var retained: WeakRef = c.factory.contexts.back()
	c.factory.retired = true
	c.client.invalidate()
	check(retained.get_ref() != null,"Awaited report retains context after live safety state is invalidated")
	c.api.release.emit()
	await process_frame
	check(result.done and not result.okay and Canonical.same(c.store.read(OWNER).value.pending,pending),"Same-epoch retired response cannot clear the saved report")
	check(await c.client.check_report() and c.client.pending_report().is_empty(),"Explicit account receipt recovery remains possible after that retirement")
	await _dispose(c)

func _report(client: RefCounted, result: Dictionary) -> void:
	result.okay = await client.report(TARGET,"privacy")
	result.done = true

func _dispose(c: Dictionary) -> void:
	c.api.queue_free()
	await process_frame
