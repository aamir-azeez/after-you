extends "res://tests/test_campaign_online_session.gd"
const CancelTests = preload("res://tests/test_campaign_lobby_cancel.gd")
const Context = preload("res://services/campaign_request_context.gd")

func _run() -> void:
	fixture = _json("res://tests/fixtures/campaign/control-v2.json")
	await _explicit_control()
	await _route_scope()
	await _mutation_capabilities()
	await _await_contexts()
	await _retirement_drains()
	await _retired_context()
	await _lobby_direction()
	await _weak_ownership()
	print("Campaign control transport: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)

func _request(c: Dictionary, method: int, path: String, body: Dictionary = {}) -> Dictionary:
	return {"owner_player_id":HOST,"identity_epoch":1,"method":method,"path":path,"body":body.duplicate(true)}

func _binding(c: Dictionary) -> Dictionary:
	var binding: Dictionary = c.owner._context()
	binding["campaign"] = c.owner.bound_campaign()
	return binding

func _explicit_control() -> void:
	var c := await _setup()
	_check(c.h.campaign_calls.size() == 1 and c.h.campaign_calls[0].path == "/v2/campaigns/"+c.anchor,"Only the explicit campaign control read uses negotiated transport")
	var count: int = c.h.campaign_calls.size()
	_check(await c.online.coordinator.refresh() and c.h.campaign_calls.size() == count,"The still-unexposed child context is not inferred from a room path")
	c.online.capabilities = {}
	_check(await c.owner.refresh() and c.h.campaign_calls.size() == count+1,"Bound control recovery GET does not require a fresh capabilities fetch")
	_check(c.h.campaign_calls[-1].body.is_empty(),"Protocol negotiation does not mutate a request body")
	c.h.free()

func _route_scope() -> void:
	var c := await _setup()
	var context := Context.new(c.owner,_binding(c))
	var root_path: String = "/v2/campaigns/"+c.anchor
	var requests := [
		_request(c,HTTPClient.METHOD_GET,"/v2/campaigns/"+"Z".repeat(22)),
		_request(c,HTTPClient.METHOD_GET,"/v2/campaigns"),
		_request(c,HTTPClient.METHOD_GET,"/v2/rooms/"+c.anchor),
		_request(c,HTTPClient.METHOD_GET,root_path+"/operations/unknown-operation-key"),
		_request(c,HTTPClient.METHOD_GET,root_path,{"unexpected":true}),
		_request(c,HTTPClient.METHOD_DELETE,root_path),
		_request(c,HTTPClient.METHOD_POST,root_path+"/continue",{}),
		_request(c,HTTPClient.METHOD_POST,root_path+"/resume",{}),
	]
	var owner_mismatch := _request(c,HTTPClient.METHOD_GET,root_path)
	owner_mismatch.owner_player_id = GUEST
	requests.append(owner_mismatch)
	var bad_type := _request(c,HTTPClient.METHOD_GET,root_path)
	bad_type.method = "GET"
	requests.append(bad_type)
	var count: int = c.h.calls.size()
	for request: Dictionary in requests:
		_check((await context.request(request)).get("ok") != true and c.h.calls.size() == count,"An unrelated route/body/identity cannot borrow a bound campaign context")
	_check((await c.owner.dispatch_campaign_request({},"control",requests[0])).get("ok") != true,"Malformed context fails without throwing or dispatching")
	c.h.free()

func _mutation_capabilities() -> void:
	for mode: String in ["unknown","control1","global","campaign","creation_only"]:
		var c := await _setup()
		c.h.view = fixture.accepted_result.campaign.duplicate(true)
		c.h.view.activation = {"transition_id":fixture.accepted_result.receipt.transition_id}
		_check(await c.owner.refresh(),"Activation debt is observed through the control read")
		var caps := Boundaries.campaign_capabilities(fixture.definition)
		match mode:
			"unknown": caps = {}
			"control1": caps.campaign_control_version = 1
			"global": caps.mutations_enabled = false
			"campaign": caps.campaign_mutations_enabled = false
			"creation_only": caps.campaign_creation_enabled = false
		c.online.capabilities = caps
		var count: int = c.h.calls.size()
		_check(not await c.owner.resume_activation(),"Unsettled activation remains explicitly recoverable under "+mode)
		if mode == "creation_only":
			_check(c.h.calls.size() == count+1 and c.h.campaign_calls[-1].path.ends_with("/resume"),"Creation pause does not disable an existing chapter activation request")
		else:
			_check(c.h.calls.size() == count and c.owner.last_code == "campaign_mutations_unavailable","Unknown or paused campaign mutation capability prevents control POST")
		_check(await c.owner.refresh(),"Mutation holds still allow control GET")
		c.h.free()

func _await_contexts() -> void:
	for mode: String in ["epoch","generation","publication"]:
		var c := await _setup()
		var context := Context.new(c.owner,_binding(c))
		var before: Dictionary = c.h.store.saved.duplicate(true)
		c.h.on_request = func():
			match mode:
				"epoch": c.h.identity_value.epoch += 1
				"generation": c.owner.invalidate_identity()
				"publication": c.owner._campaign._state.view.revision += 1
		var reply: Dictionary = await context.request(_request(c,HTTPClient.METHOD_GET,"/v2/campaigns/"+c.anchor))
		_check(reply.get("ok") != true and reply.code == "campaign_context_changed","A delayed control response is discarded after "+mode+" changes")
		_check(Canonical.same(before,c.h.store.saved),"Discarding a stale response does not overwrite journal evidence")
		c.h.on_request = Callable()
		c.h.free()

func _retirement_drains() -> void:
	var c := await _setup()
	var completed := {"done":false,"okay":true}
	c.h.on_request = func():
		c.h.identity_value.epoch += 1
		c.owner.invalidate_identity()
		_check(c.owner.restore_owner(),"The new epoch can restore while its old control request drains")
	_finish_refresh(c.owner,completed)
	for frame in range(20):
		if completed.done: break
		await process_frame
	_check(completed.done and not completed.okay,"Retiring the actual session context still completes its old awaited request")
	c.h.on_request = Callable()
	c.h.free()

func _finish_refresh(owner: RefCounted, result: Dictionary) -> void:
	result.okay = await owner.refresh()
	result.done = true

func _retired_context() -> void:
	var c := await _setup()
	var context := Context.new(c.owner,_binding(c))
	var request := _request(c,HTTPClient.METHOD_GET,"/v2/campaigns/"+c.anchor)
	_check(c.owner.release_for_ordinary(),"A settled selected child can explicitly release campaign ownership")
	var count: int = c.h.calls.size()
	_check((await context.request(request)).get("ok") != true and c.h.calls.size() == count,"Retained callbacks cannot send after owner release")
	c.h.free()

func _lobby_direction() -> void:
	# Reuse only its actual API harness; setup is hosted by this SceneTree.
	var h := CancelTests.CancelHarness.new()
	root.add_child(h)
	h.view = fixture.active_view.duplicate(true)
	h.capabilities = Boundaries.campaign_capabilities(fixture.definition)
	var online := Online.new(h,h.identity,h.store)
	var owner := Owner.new(online,h.identity,[fixture.definition],h.leave_ready,h.store)
	_check(await owner.load_campaign_lobby(),"Lobby loads with ordinary capabilities and an explicit marked list")
	_check(h.calls[0].path == "/v2/capabilities" and h.campaign_calls.size() == 1 and h.campaign_calls[0].path == "/v2/campaigns","Capabilities do not inherit a campaign header from the following list")
	h.fail_post = true
	await owner.create_campaign(Protocol.key(fixture.definition))
	var pending: Dictionary = owner.pending_lobby()
	_check(Canonical.same(h.campaign_calls[-1].body,pending.body),"Marked admission sends the exact saved request body")
	h.fail_cancel = true
	await owner.cancel_lobby_request()
	var count: int = h.calls.size()
	var request := {"owner_player_id":HOST,"identity_epoch":1,"method":HTTPClient.METHOD_POST,"path":pending.path,"body":pending.body}
	_check((await owner.dispatch_campaign_request(owner._context(),"lobby",request)).get("ok") != true and h.calls.size() == count,"A sticky Cancel intent cannot borrow transport for its former admission direction")
	var saved: Dictionary = owner.pending_lobby()
	for mode: String in ["old_control","missing_control"]:
		h.capabilities = Boundaries.campaign_capabilities(fixture.definition)
		if mode == "old_control": h.capabilities.campaign_control_version = 1
		else: h.capabilities.erase("campaign_control_version")
		_check(await online.load_capabilities(),"Ordinary capability refresh observes "+mode+" while global mutation stays enabled")
		count = h.calls.size()
		_check(not await owner.cancel_lobby_request() and h.calls.size() == count and Canonical.same(saved,owner.pending_lobby()),"A stale lobby capability cache cannot send or rewrite a saved Cancel")
	h.capabilities = Boundaries.campaign_capabilities(fixture.definition)
	_check(await online.load_capabilities(),"Current control2 capability can explicitly restore dispatch")
	h.fail_cancel = false
	_check(await owner.cancel_lobby_request() and h.campaign_calls[-1].path.ends_with("/cancel"),"Fenced cancellation uses explicit campaign transport")
	var ordinary_count: int = h.campaign_calls.size()
	await online.load_capabilities()
	_check(h.campaign_calls.size() == ordinary_count,"A later ordinary capability read remains unmarked")
	h.free()

func _weak_ownership() -> void:
	var c := await _setup()
	var context := Context.new(c.owner,_binding(c))
	var reference: WeakRef = weakref(c.owner)
	var request := _request(c,HTTPClient.METHOD_GET,"/v2/campaigns/"+c.anchor)
	c.owner = null
	# The setup coroutine resumed us inside its final request callback. Let its
	# completed stack release local references before testing retained ownership.
	await process_frame
	_check(reference.get_ref() == null,"A retained transport context does not retain its old owner")
	_check((await context.request(request)).get("ok") != true,"An expired owner makes the retained callback inert")
	c.h.free()
