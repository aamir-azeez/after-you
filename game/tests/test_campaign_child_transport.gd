extends "res://tests/test_campaign_owned_restore.gd"

func _run() -> void:
	fixture = _json("res://tests/fixtures/campaign/control-v2.json")
	await _explicit_child()
	await _probe_adoption()
	await _route_bounds()
	await _response_binding()
	await _membership_catchup()
	await _publication_holds()
	await _old_pending()
	await _child_awaits()
	await _probe_retirement()
	await _weak_child()
	await _invalidated_child()
	print("Campaign child transport: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)

func _explicit_child() -> void:
	var c := await _make()
	_check(c.h.campaign_calls.size() == 2 and c.h.campaign_calls[-1].path == "/v2/rooms/"+c.anchor,"An isolated target probe uses explicit campaign negotiation")
	var count: int = c.h.campaign_calls.size()
	_check(await c.online.coordinator.refresh() and c.h.campaign_calls.size() == count+1,"The adopted candidate retains its scoped child transport")
	var record := _json("res://tests/fixtures/cooperative/upper-path-a.json")
	_check(not await c.online.coordinator.commit(record),"A lost child commit remains recoverable")
	var pending: Dictionary = c.online.coordinator.pending()
	_check(not pending.is_empty() and c.h.campaign_calls[-1].path == "/v2/rooms/"+c.anchor+"/turns" and Canonical.same(c.h.campaign_calls[-1].body,pending.body),"Scoped gameplay sends only its exact saved native pending body")
	count = c.h.campaign_calls.size()
	_check(not await c.online.coordinator.reconcile() and c.h.campaign_calls.size() == count+2,"Known missing receipt reconciles with marked GET and the same marked POST")
	_check(Canonical.same(c.online.coordinator.pending(),pending),"Retry preserves the original key, recording and pending journal")
	c.h.free()

func _probe_adoption() -> void:
	var c := await _make()
	c.h.view = fixture.accepted_result.campaign.duplicate(true)
	_check(await c.owner.refresh(),"Next published chapter is available")
	var source: RefCounted = c.online.coordinator
	var before: Dictionary = c.h.store.saved[_room_scope(c.anchor)].duplicate(true)
	_check(await c.owner.select_current(),"The exact target is verified in isolation")
	var target: RefCounted = c.owner._bridge._candidate
	_check(target != null and not target.my_turn() and target.create_live_simulation() == null,"A verified but unadopted candidate cannot create gameplay")
	_check(c.online.coordinator == source and c.online.last_room() == c.anchor and Canonical.same(before,c.h.store.saved[_room_scope(c.anchor)]),"Target verification leaves the visible source and its saved proof unchanged")
	_check(c.owner.adopt_selected() and c.online.coordinator == target and target.my_turn(),"Only exact durable selection plus coordinator adoption enables the same candidate")
	_check(not source.my_turn() and source.create_live_simulation() == null,"The retained former coordinator cannot create fresh gameplay")
	var count: int = c.h.calls.size()
	_check(not await source.refresh() and c.h.calls.size() == count,"A replaced selected child cannot borrow a new target's authority")
	_check(await target.refresh(),"The adopted target can still refresh through its original context")
	c.h.free()

func _route_bounds() -> void:
	var c := await _make()
	var context: RefCounted = c.online.coordinator._transport_lifetime
	var path: String = "/v2/rooms/"+c.anchor
	var cases := [
		[HTTPClient.METHOD_GET,"/v2/rooms/"+c.target,{}],
		[HTTPClient.METHOD_GET,path+"/operations/unsaved-key",{}],
		[HTTPClient.METHOD_GET,path+"/photos",{}],
		[HTTPClient.METHOD_GET,path+"/pairs/p0-0/trailing",{}],
		[HTTPClient.METHOD_GET,path,{"unexpected":true}],
		[HTTPClient.METHOD_POST,path+"/turns",{}],
		[HTTPClient.METHOD_POST,path+"/fork",{}],
		[HTTPClient.METHOD_DELETE,path,{}],
		[HTTPClient.METHOD_POST,"/v2/campaigns/"+c.anchor+"/continue",{}]]
	var count: int = c.h.calls.size()
	for item: Array in cases:
		var response: Dictionary = await context.request({"owner_player_id":HOST,"identity_epoch":1,"method":item[0],"path":item[1],"body":item[2]})
		_check(response.get("ok") != true and c.h.calls.size() == count,"A child context refuses unrelated routes and unsaved requests")
	var ordinary_count: int = c.h.campaign_calls.size()
	await c.online.transport({"owner_player_id":HOST,"identity_epoch":1,"method":HTTPClient.METHOD_GET,"path":path,"body":{}})
	_check(c.h.campaign_calls.size() == ordinary_count,"A raw ordinary transport request is never implicitly marked by its path")
	c.h.free()

func _publication_holds() -> void:
	for mode: String in ["advanced","continuing","activation","member","release"]:
		var c := await _make()
		var child: RefCounted = c.online.coordinator
		var live: RefCounted = child.create_live_simulation()
		_check(live != null,"A current owned child starts a native rehearsal")
		live.step({"move_x":1.0})
		if mode == "release": _check(c.owner.release_for_ordinary(),"Settled owner releases explicitly")
		else:
			match mode:
				"advanced": c.h.view = fixture.accepted_result.campaign.duplicate(true)
				"continuing": c.h.view = fixture.pending_result.campaign.duplicate(true)
				"activation":
					c.h.view = fixture.accepted_result.campaign.duplicate(true)
					c.h.view.activation = {"transition_id":fixture.accepted_result.receipt.transition_id}
				"member":
					# A replacement member is never valid; hold the local owner just
					# as a malformed/unsupported publication must hold gameplay.
					c.owner.read_only = true
			if mode != "member": _check(await c.owner.refresh(),"The owner observes "+mode+" publication")
		var before: Dictionary = c.h.store.saved.duplicate(true)
		var count: int = c.h.calls.size()
		_check(child.campaign_recovery_only() and not child.my_turn() and child.create_live_simulation() == null and not child.save_live_draft(live) and not child.save_draft(live.export_recording()),"Changed "+mode+" authority exposes recovery and refuses fresh native input and save")
		_check(not await child.fork(0) and not await child.commit(_json("res://tests/fixtures/cooperative/upper-path-a.json")),"Changed authority cannot create a new fork or turn intent")
		_check(c.h.calls.size() == count and Canonical.same(before,c.h.store.saved),"Authority holds preserve all existing durable journals")
		c.h.free()

func _response_binding() -> void:
	for mode: String in ["member","pin","simulation","room"]:
		var c := await _make()
		var before: Dictionary = c.h.store.saved.duplicate(true)
		match mode:
			"member": c.h.rooms[c.anchor].guest_id = OTHER
			"pin": c.h.rooms[c.anchor].definition_hash = "a".repeat(64)
			"simulation": c.h.rooms[c.anchor].simulation_version = 5
			"room": c.h.rooms[c.anchor].room_id = OTHER
		_check(not await c.online.coordinator.refresh() and c.online.coordinator.last_code == "campaign_room_mismatch","Child transport refuses a response with a different "+mode+" binding")
		_check(Canonical.same(before,c.h.store.saved),"Mismatched response authority is rejected before any room journal write")
		c.h.free()
	var c := await _make()
	c.h.rooms[c.anchor] = _prepare_b(c)
	_check(await c.online.coordinator.refresh(),"Real stage-two A proof enables final B receipt validation")
	_check(not await c.online.coordinator.commit(_json("res://tests/fixtures/cooperative/down-and-around-b.json")),"Final B has an exact retained request")
	var pending: Dictionary = c.online.coordinator.pending()
	var complete := _room("high-and-low",c.anchor,true)
	complete.revision = 5
	complete.guest_id = OTHER
	c.h.operation_reply = {"ok":true,"status":200,"data":_b_receipt(pending,complete)}
	var before: Dictionary = c.h.store.saved.duplicate(true)
	_check(not await c.online.coordinator.reconcile() and c.online.coordinator.last_code == "campaign_room_mismatch","An otherwise accepted receipt cannot substitute a different published partner")
	_check(Canonical.same(before,c.h.store.saved) and Canonical.same(pending,c.online.coordinator.pending()),"Receipt binding failure preserves the saved B and every journal")
	c.h.free()

func _old_pending() -> void:
	var c := await _make()
	c.h.rooms[c.anchor] = _prepare_b(c)
	_check(await c.online.coordinator.refresh(),"Real stage-two A proof enables a final B request")
	_check(not await c.online.coordinator.commit(_json("res://tests/fixtures/cooperative/down-and-around-b.json")),"An actual native final B is saved before later publication")
	var pending: Dictionary = c.online.coordinator.pending()
	c.h.view = fixture.accepted_result.campaign.duplicate(true)
	_check(await c.owner.refresh(),"A later chapter publication does not erase old pending work")
	var count: int = c.h.campaign_calls.size()
	_check(not await c.online.coordinator.reconcile() and c.h.campaign_calls.size() == count+2,"An already-owned historical child can reconcile its exact retained request")
	_check(Canonical.same(pending,c.online.coordinator.pending()),"Historical retry preserves the exact saved request")
	var cold := _cold(c)
	_check(cold.owner.restore_selected_room(),"Cold historical restoration creates a new exact owner context")
	count = c.h.campaign_calls.size()
	_check(not await cold.online.coordinator.reconcile() and c.h.campaign_calls.size() == count+2,"The cold context retains marked receipt recovery")
	_check(not cold.online.coordinator.my_turn(),"Historical recovery never enables fresh gameplay")
	c.h.free()

func _membership_catchup() -> void:
	var h := RestoreHarness.new()
	root.add_child(h)
	h.view = fixture.active_view.duplicate(true)
	h.view.state = "waiting"
	h.view.guest_id = null
	h.view.revision = 0
	var anchor: String = h.view.campaign_room_id
	h.rooms[anchor] = _room("high-and-low",anchor,false)
	h.rooms[anchor].guest_id = null
	var online := Online.new(h,h.identity,h.store)
	_check(await online.open_room(anchor),"Host cache exists before the friend joins")
	online.capabilities = Boundaries.campaign_capabilities(fixture.definition)
	var owner := Owner.new(online,h.identity,[fixture.definition],h.leave_ready,h.store)
	_check(owner.restore_owner() and owner.bind_campaign(anchor,Protocol.key(fixture.definition)) and await owner.refresh() and await owner.select_current() and owner.adopt_selected(),"A waiting campaign adopts its exact guest-null child")
	h.view = fixture.active_view.duplicate(true)
	h.rooms[anchor].guest_id = GUEST
	h.rooms[anchor].revision += 1
	var before: Dictionary = h.store.saved[_room_scope(anchor)].duplicate(true)
	_check(not await online.coordinator.refresh() and Canonical.same(before,h.store.saved[_room_scope(anchor)]),"A room alone cannot silently change the campaign's recorded partner")
	_check(await owner.refresh() and await online.coordinator.refresh(),"An explicit control GET followed by child GET catches up to the accepted friend")
	_check(owner.view().guest_id == GUEST and online.coordinator.snapshot().guest_id == GUEST and online.coordinator.my_turn(),"Validated additive membership restores ordinary chapter play")
	_check(_only_gets(h.calls),"Membership catch-up neither submits a turn nor advances the story")
	h.free()

func _child_awaits() -> void:
	for mode: String in ["epoch","retire","publication","selection"]:
		var c := await _make()
		var before: Dictionary = c.h.store.saved.duplicate(true)
		c.h.on_request = func():
			match mode:
				"epoch": c.h.identity_value.epoch += 1
				"retire": c.owner.invalidate_identity()
				"publication": c.owner._campaign._state.view.revision += 1
				"selection": c.online._room_selection_generation += 1
		var result := {"done":false,"okay":true}
		_finish_child(c.online.coordinator,result)
		for frame in range(20):
			if result.done: break
			await process_frame
		_check(result.done and not result.okay,"A delayed child request finishes and rejects changed "+mode+" authority")
		_check(Canonical.same(before,c.h.store.saved),"A stale child response cannot overwrite durable state")
		c.h.on_request = Callable()
		c.h.free()

func _finish_child(child: RefCounted, result: Dictionary) -> void:
	result.okay = await child.refresh()
	result.done = true

func _probe_retirement() -> void:
	var c := await _make()
	c.h.view = fixture.accepted_result.campaign.duplicate(true)
	_check(await c.owner.refresh(),"Next target is published before the retirement test")
	var before: Dictionary = c.h.store.saved.duplicate(true)
	c.h.on_request = func():
		c.h.identity_value.epoch += 1
		c.owner.invalidate_identity()
		_check(c.owner.restore_owner(),"New owner restores while the previous target probe drains")
	var result := {"done":false,"okay":true}
	_finish_selection(c.owner,result)
	for frame in range(20):
		if result.done: break
		await process_frame
	_check(result.done and not result.okay,"Retiring the actual borrowed Bridge callback does not lose its coroutine")
	_check(Canonical.same(before,c.h.store.saved) and c.online.last_room() == c.anchor,"Retired target probe neither saves selection nor adopts")
	c.h.on_request = Callable()
	c.h.free()

func _finish_selection(owner: RefCounted, result: Dictionary) -> void:
	result.okay = await owner.select_current()
	result.done = true

func _weak_child() -> void:
	var c := await _make()
	var child: RefCounted = c.online.coordinator
	var owner_ref: WeakRef = weakref(c.owner)
	c.owner = null
	await process_frame
	_check(owner_ref.get_ref() == null,"A retained coordinator and context do not retain the retired owner")
	var count: int = c.h.calls.size()
	_check(not child.my_turn() and not await child.refresh() and c.h.calls.size() == count,"Expired owner callbacks are inert")
	c.h.free()

func _invalidated_child() -> void:
	var c := await _make()
	var child: RefCounted = c.online.coordinator
	c.owner.invalidate_identity()
	var before: Dictionary = c.h.store.saved.duplicate(true)
	var count: int = c.h.calls.size()
	_check(not child.my_turn() and child.create_live_simulation() == null and child.campaign_recovery_only(),"An invalidated but retained owner safely holds fresh input")
	_check(not child.save_draft(_json("res://tests/fixtures/cooperative/upper-path-a.json")) and not await child.fork(0),"Retained callbacks cannot revive an invalidated owner's empty lobby")
	_check(not await child.refresh() and c.h.calls.size() == count and Canonical.same(before,c.h.store.saved),"Invalidated owner callbacks neither dispatch nor rewrite recovery")
	c.h.free()
