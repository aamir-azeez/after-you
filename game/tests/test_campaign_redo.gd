extends "res://tests/test_campaign_owned_restore.gd"
const StoryRedo = preload("res://services/campaign_redo_client.gd")
const OrdinaryRedo = preload("res://services/redo_client.gd")
const Capabilities = preload("res://services/campaign_capabilities.gd")

class RedoHarness:
	extends RestoreHarness
	var advisory: Variant = null
	var receipts: Dictionary = {}
	var drop_post := false
	var refuse_lookup := ""
	func request_json(method: int, path: String, body: Dictionary = {}) -> Dictionary:
		if "/redo" not in path: return await super.request_json(method,path,body)
		busy = true
		calls.append({"method":method,"path":path,"body":body.duplicate(true)})
		if on_request.is_valid(): on_request.call()
		if hold: await release
		else: await get_tree().process_frame
		var reply := _redo_reply(method,path,body)
		busy = false
		if method == HTTPClient.METHOD_POST and drop_post:
			drop_post = false
			return {"ok":false,"status":0,"code":"connection_interrupted"}
		return reply
	func _redo_reply(method: int, path: String, body: Dictionary) -> Dictionary:
		var index := int(path.get_slice("/",5))
		var room_id: String = view.chapters[index].room_id
		var binding := {"campaign_room_id":view.campaign_room_id,"campaign_key":view.campaign_key,"chapter_index":index,"chapter":view.chapters[index].chapter,"room_id":room_id}
		var room: Dictionary = rooms[room_id]
		var source := OrdinaryRedo.source_for("relay",room)
		if "/operations/" in path:
			if not refuse_lookup.is_empty(): return {"ok":false,"status":404,"code":refuse_lookup}
			return {"ok":true,"status":200,"data":receipts[path.get_file()].duplicate(true)} if receipts.has(path.get_file()) else {"ok":false,"status":404,"code":"operation_not_found"}
		if method == HTTPClient.METHOD_POST:
			if not Canonical.same(body.source,source): return {"ok":false,"status":409,"code":"redo_source_changed"}
			if path.ends_with("/accept"):
				var op := {"source":source,"body":body}
				var hashed := StoryRedo.fork_body(op)
				hashed.operation = "fork"
				var receipt := {"schema_version":2,"room_id":room_id,"idempotency_key":body.idempotency_key,"request_hash":Canonical.digest(hashed),"operation":"fork","accepted_revision":room.revision+1,"branch":room.branch+1,"stage_index":room.stage_index,"stage_id":room.stage_id,"checkpoint_hash":room.checkpoint.checkpoint_hash,"turn_id":null,"recording_hash":null,"pair_id":null}
				room.revision += 1
				room.branch += 1
				room.active_role = "a"
				room.active_player_id = room.first_player_id
				room.recording_a = null
				room.a_turn_id = null
				var result := {"schema_version":1,"binding":binding,"receipt":receipt}
				receipts[body.idempotency_key] = result.duplicate(true)
				return {"ok":true,"status":200,"data":result}
			advisory = {"request_id":Canonical.digest(source),"source":source,"status":{"request":"pending","decline":"declined","cancel":"cancelled"}[body.action]}
		var current: Variant = advisory if advisory is Dictionary and Canonical.same(advisory.source,source) else null
		return {"ok":true,"status":200,"data":{"schema_version":1,"binding":binding,"redo":{"schema_version":1,"source":null if source.is_empty() else source,"request":current}}}

func _run() -> void:
	fixture = _json("res://tests/fixtures/campaign/control-v2.json")
	_wire_and_capability()
	for stage: int in [0,1]:
		await _advisory_draft(stage)
		await _accept_cold(stage)
	await _advisory_overtaken(false)
	await _advisory_overtaken(true)
	await _draft_after_partner_accept(false)
	await _draft_after_partner_accept(true)
	await _accepted_storage_hold()
	await _historical_accept()
	await _consent_loses_to_b()
	await _uncertain_denial()
	await _identity_callback()
	await _review_ui()
	await _completed_redo_ui(true)
	await _completed_redo_ui(false)
	print("Story handoff redo: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)

func _make_redo(stage: int, first: bool) -> Dictionary:
	var h := RedoHarness.new()
	h.store = RestoreStore.new()
	root.add_child(h)
	h.view = fixture.active_view.duplicate(true)
	var anchor: String = h.view.campaign_room_id
	var room := _room("high-and-low",anchor,false)
	h.rooms[anchor] = room
	if stage == 1: h.rooms[anchor] = _prepare_b({"h":h,"anchor":anchor})
	else:
		h.rooms[anchor].revision = 2
		h.rooms[anchor].recording_a = _json("res://tests/fixtures/cooperative/upper-path-a.json")
		h.rooms[anchor].a_turn_id = "t0-0-a"
		h.rooms[anchor].active_role = "b"
		h.rooms[anchor].active_player_id = GUEST
	var player: String = h.rooms[anchor].first_player_id if first else h.rooms[anchor].active_player_id
	h.player_id = player
	h.identity_value.player_id = player
	if player == GUEST:
		h.view.player_slot = "p1"
		h.view.invite_code = null
		h.view.invite_expires_at = null
		h.rooms[anchor].player_slot = "p1"
		h.rooms[anchor].erase("invite_code")
	var online := Online.new(h,h.identity,h.store)
	_check(await online.open_room(anchor),"Redo fixture verifies the actual A/checkpoint proof")
	online.capabilities = Boundaries.campaign_capabilities(fixture.definition)
	online.capabilities["campaign_redo_version"] = 1
	var owner := Owner.new(online,h.identity,[fixture.definition],h.leave_ready,h.store)
	_check(owner.restore_owner() and owner.bind_campaign(anchor,Protocol.key(fixture.definition)),"Redo owner binds durably")
	_check(await owner.refresh() and await owner.select_current() and owner.adopt_selected(),"Redo uses an adopted Story child")
	return {"h":h,"online":online,"owner":owner,"anchor":anchor}

func _advisory_draft(stage: int) -> void:
	var c := await _make_redo(stage,false)
	var live: RefCounted = c.online.coordinator.create_live_simulation()
	live.step()
	_check(c.online.coordinator.save_live_draft(live),"An unsuccessful B attempt is saved before asking")
	var draft: Dictionary = c.online.coordinator.draft()
	var client: RefCounted = c.owner.redo_client()
	_check(await client.refresh() and client.can_request() and not client.can_accept(),"Stage %d B can ask, never consent" % stage)
	_check(await client.request_redo() and client.can_cancel(),"Request resolves without holding ordinary B rehearsal")
	_check(Canonical.same(c.online.coordinator.draft(),draft) and c.online.coordinator.my_turn(),"Asking preserves the B draft and allows a valid later attempt")
	_check(await client.cancel() and Canonical.same(c.online.coordinator.draft(),draft),"Cancel preserves exact B draft bytes")
	c.h.free()

func _seed_request(c: Dictionary) -> void:
	var source := OrdinaryRedo.source_for("relay",c.h.rooms[c.anchor])
	c.h.advisory = {"request_id":Canonical.digest(source),"source":source,"status":"pending"}

func _accept_cold(stage: int) -> void:
	var c := await _make_redo(stage,true)
	_seed_request(c)
	var client: RefCounted = c.owner.redo_client()
	_check(await client.refresh() and client.can_accept() and not client.can_request(),"Stage %d actual A author consents" % stage)
	c.h.drop_post = true
	_check(not await client.accept() and not client.pending().is_empty(),"Lost acceptance keeps its exact child operation")
	var saved: Dictionary = client.pending()
	var cold := _cold(c)
	cold.online.capabilities = Boundaries.campaign_capabilities(fixture.definition)
	cold.online.capabilities["campaign_redo_version"] = 1
	cold.online.capabilities.campaign_mutations_enabled = false
	_check(cold.owner.restore_selected_room(),"Cold redo restores its selected child for recovery")
	client = cold.owner.redo_client()
	_check(Canonical.same(client.pending(),saved) and not cold.owner.can_leave() and cold.online.coordinator.create_live_simulation() == null,"Cold uncertain redo holds fresh input and departure")
	var calls: int = c.h.calls.size()
	_check(await client.retry(false) and client.accepted and client.pending().is_empty(),"Paused recovery reads the exact receipt and settles normally")
	_check(_only_gets(c.h.calls.slice(calls)) and c.h.receipts.size() == 1,"Accepted recovery sends no second fork")
	_check(cold.online.coordinator.snapshot().branch == 1 and cold.online.coordinator.snapshot().stage_index == stage,"Redo resets only the current pair")
	if stage == 1: _check(cold.online.coordinator.snapshot().completed_pair_ids == ["p0-0"],"Earlier pair history remains unchanged")
	c.h.free()

func _advisory_overtaken(advance: bool) -> void:
	var c := await _make_redo(0,false)
	var client: RefCounted = c.owner.redo_client()
	_check(await client.refresh(),"Advisory recovery reads the actual source")
	c.h.drop_post = true
	_check(not await client.request_redo() and client.held(),"Lost advisory is retained")
	if advance:
		c.h.rooms[c.anchor].revision += 1
		c.h.rooms[c.anchor].branch += 1
		c.h.rooms[c.anchor].active_role = "a"
		c.h.rooms[c.anchor].active_player_id = HOST
		c.h.rooms[c.anchor].recording_a = null
		c.h.rooms[c.anchor].a_turn_id = null
	else: c.h.advisory.status = "declined"
	var calls: int = c.h.calls.size()
	_check(await client.retry(false) and not client.held(),"A later terminal/source state retires only the superseded advisory")
	_check(_only_gets(c.h.calls.slice(calls)),"Advisory recovery does not retransmit a superseded request")
	if advance: _check(c.online.coordinator.snapshot().branch == 1 and not c.online.coordinator.my_turn(),"Superseded advisory adopts the new branch before unlocking play")
	c.h.free()

func _draft_after_partner_accept(full: bool) -> void:
	var c := await _make_redo(1,false)
	var child: RefCounted = c.online.coordinator
	var live: RefCounted = child.create_live_simulation()
	live.step()
	_check(child.save_live_draft(live),"Partner-redo fixture retains actual native B draft")
	var draft: Dictionary = child._state.draft.duplicate(true)
	if full:
		var state: Dictionary = child._state.duplicate(true)
		for i in range(child.MAX_HELD): state.held_drafts.append(draft.duplicate(true))
		_check(child._persist(state),"Fixture fills the existing bounded history")
	var before: Dictionary = child._state.duplicate(true)
	var client: RefCounted = c.owner.redo_client()
	await client.refresh()
	c.h.drop_post = true
	await client.request_redo()
	var op: Dictionary = client.pending()
	var body := {"schema_version":1,"binding":op.binding,"source":op.source,"request_id":Canonical.digest(op.source),"idempotency_key":"synthetic-partner-redo-0001"}
	c.h._redo_reply(HTTPClient.METHOD_POST,StoryRedo.path_for(op.binding)+"/accept",body)
	var okay: bool = await client.retry(false)
	if full:
		_check(not okay and client.held() and Canonical.same(child._state,before),"Full history preserves old B draft and holds superseded request recovery")
	else:
		_check(okay and child.draft().is_empty() and child._state.held_drafts.size() == 1,"Partner consent moves the stale B draft through normal adoption")
		_check(Canonical.same(child._state.held_drafts[0],draft) and child.snapshot().completed_pair_ids == ["p0-0"],"Held draft keeps its old source and accepted pair history")
	c.h.free()

func _accepted_storage_hold() -> void:
	var c := await _make_redo(0,true)
	_seed_request(c)
	var client: RefCounted = c.owner.redo_client()
	_check(await client.refresh(),"Settlement fixture reads consent")
	c.h.store.fail_scope = "relay-room-v2:"+HOST+":"+c.anchor
	_check(not await client.accept() and client.settlement_pending() and not client.accepted,"Accepted receipt is durable even when local child save fails")
	var saved: Dictionary = client.pending()
	c.h.store.fail_scope = ""
	var calls: int = c.h.calls.size()
	_check(await client.retry(false) and client.accepted and c.h.receipts.size() == 1,"Settlement retry adopts without accepting again")
	_check(_only_gets(c.h.calls.slice(calls)) and saved.accepted_receipt.operation == "fork","Retry uses preserved accepted evidence")
	c.h.free()

func _uncertain_denial() -> void:
	var c := await _make_redo(0,true)
	_seed_request(c)
	var client: RefCounted = c.owner.redo_client()
	await client.refresh()
	c.h.drop_post = true
	await client.accept()
	var saved: Dictionary = client.pending()
	for code: String in ["room_not_found","room_deleted","room_blocked"]:
		c.h.refuse_lookup = code
		_check(not await client.retry() and Canonical.same(client.pending(),saved),"Current denial never erases unknown acceptance: "+code)
	c.h.free()

func _historical_accept() -> void:
	var c := await _make_redo(0,true)
	_seed_request(c)
	var client: RefCounted = c.owner.redo_client()
	await client.refresh()
	c.h.drop_post = true
	await client.accept()
	var saved: Dictionary = client.pending()
	var completed := _room("high-and-low",c.anchor,true)
	completed.revision = 7
	completed.branch = 1
	completed.completed_pair_ids = ["p1-0","p1-1"]
	c.h.rooms[c.anchor] = completed
	c.h.view = fixture.accepted_result.campaign.duplicate(true)
	c.h.view.chapters[0].completion.source_revision = 7
	c.h.view.chapters[0].completion.source_branch = 1
	var target: String = c.h.view.chapters[1].room_id
	c.h.rooms[target] = _room("rolling-home",target,false)
	_check(await c.owner.refresh(),"Later publication does not erase the old redo intent")
	var cold := _cold(c)
	cold.online.capabilities = Boundaries.campaign_capabilities(fixture.definition)
	cold.online.capabilities["campaign_redo_version"] = 1
	_check(cold.owner.restore_selected_room() and cold.online.coordinator.campaign_recovery_only(),"Cold restore binds the exact historical selected child read-only")
	client = cold.owner.redo_client()
	var calls: int = c.h.calls.size()
	_check(Canonical.same(client.pending(),saved) and await client.retry(false),"Historical receipt settles against its saved chapter and key")
	_check(c.h.calls[calls].path == StoryRedo.path_for(saved.binding)+"/operations/"+saved.body.idempotency_key and _only_gets(c.h.calls.slice(calls)),"History recovery never retargets the new chapter or resubmits")
	_check(cold.owner.selected_room() == c.anchor and cold.online.coordinator.chapter_complete(),"Receipt recovery does not adopt the newer chapter")
	_check(await cold.owner.select_current() and cold.owner.adopt_selected() and cold.online.last_room() == target,"Separate ordinary handoff adopts the new published chapter after recovery")
	c.h.free()

func _consent_loses_to_b() -> void:
	var c := await _make_redo(0,true)
	_seed_request(c)
	var client: RefCounted = c.owner.redo_client()
	await client.refresh()
	c.h.on_request = func():
		if c.h.calls[-1].path.ends_with("/accept"):
			c.h.rooms[c.anchor] = _room("high-and-low",c.anchor,true)
	_check(not await client.accept() and client.held() and c.h.receipts.is_empty(),"B completion wins before consent transaction")
	c.h.on_request = Callable()
	var calls: int = c.h.calls.size()
	_check(await client.retry(false) and not client.held() and not client.accepted,"Verified newer source and second missing receipt retire the losing intent")
	var reads: Array = c.h.calls.slice(calls)
	_check(_only_gets(reads) and reads[0].path.contains("/operations/") and reads[-1].path == reads[0].path,"B-wins recovery brackets the verified source with exact-key lookups")
	_check(c.online.coordinator.chapter_complete() and c.h.receipts.is_empty(),"Winning B history remains complete without a fork")
	c.h.free()

func _review_ui() -> void:
	var c := await _make_redo(0,false)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280,720)
	viewport.own_world_3d = true
	root.add_child(viewport)
	var preview := preload("res://relay_preview.gd").new()
	preview.online_session = c.online
	preview.settings = {"sound":false,"music":false,"reduced_motion":true}
	preview.reaction_photos_enabled = false
	preview.campaign_redo_client = c.owner.redo_client
	preview.campaign_card_state = func() -> Dictionary: return {"actions":[]}
	preview.campaign_card_action = func(_action: String) -> void: pass
	viewport.add_child(preview)
	preview.set_process(false)
	preview.set_physics_process(false)
	preview._begin()
	preview.sim.step()
	preview._finish()
	var draft: Dictionary = preview.journey.draft()
	var actions := preview.overlay.find_children("*","Button",true,false)
	_check(preview.mode == "review" and actions.any(func(button: Button) -> bool: return button.text == "Request redo"),"Stopped unsuccessful B review exposes Request redo")
	_check(not preview.story_boundary_ready(true) and not preview._ordinary_redo_available(),"Review does not open dialogue/Continue or ordinary child redo")
	preview._open_campaign_redo()
	for i in range(6): await process_frame
	var screen: CanvasLayer = preview._redo_screen
	_check(is_instance_valid(screen) and preview.mode == "redo_requests" and not preview.running,"Existing consent screen pauses gameplay")
	await screen._act("request")
	screen.close()
	await process_frame
	_check(preview.mode == "review" and not preview.running and Canonical.same(preview.journey.draft(),draft),"Closing a settled request returns to the same saved review without recording")
	viewport.queue_free()
	await process_frame
	await process_frame
	c.h.free()

func _identity_callback() -> void:
	var c := await _make_redo(0,false)
	var client: RefCounted = c.owner.redo_client()
	await client.refresh()
	c.h.on_request = func(): c.h.identity_value.epoch += 1
	_check(not await client.request_redo() and not client.available(),"Identity change during dispatch cannot adopt an old callback")
	c.h.free()

func _completed_redo_ui(accepted: bool) -> void:
	var c := await _make_redo(0,true)
	_seed_request(c)
	var client: RefCounted = c.owner.redo_client()
	await client.refresh()
	if accepted:
		c.h.drop_post = true
	else:
		c.h.on_request = func():
			if c.h.calls[-1].path.ends_with("/accept"):
				c.h.rooms[c.anchor] = _room("high-and-low",c.anchor,true)
	_check(not await client.accept() and client.held(),"Completed-card fixture retains the interrupted consent operation")
	c.h.on_request = Callable()
	if accepted:
		var completed := _room("high-and-low",c.anchor,true)
		completed.revision = 7
		completed.branch = 1
		completed.completed_pair_ids = ["p1-0","p1-1"]
		c.h.rooms[c.anchor] = completed
	var room_scope: String = "relay-room-v2:"+HOST+":"+c.anchor
	var redo_scope: String = "relay-campaign-redo-v1:"+HOST+":"+c.anchor
	c.h.store.on_save = func(scope: String):
		if scope == room_scope: c.h.store.fail_scope = redo_scope
	_check(not await client.retry(false) and client.held() and c.online.coordinator.chapter_complete(),"Completed snapshot saves before the redo journal clear fails")
	_check(client.settlement_pending() == accepted,"Saved recovery distinguishes accepted receipt from obsolete consent")
	var pending: Dictionary = client.pending()
	c.h.store.fail_scope = ""
	c.h.store.on_save = Callable()
	var cold := _cold(c)
	cold.online.capabilities = Boundaries.campaign_capabilities(fixture.definition)
	cold.online.capabilities["campaign_redo_version"] = 1
	_check(cold.owner.restore_selected_room() and cold.online.coordinator.chapter_complete(),"Cold entry restores the completed selected child with its redo hold")
	client = cold.owner.redo_client()
	_check(Canonical.same(client.pending(),pending),"Cold entry retains exact consent key and any accepted receipt")
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280,720)
	viewport.own_world_3d = true
	root.add_child(viewport)
	var preview := preload("res://relay_preview.gd").new()
	preview.online_session = cold.online
	preview.settings = {"sound":false,"music":false,"reduced_motion":true}
	preview.reaction_photos_enabled = false
	preview.campaign_redo_client = cold.owner.redo_client
	preview.campaign_card_state = func() -> Dictionary: return {"actions":[]}
	preview.campaign_card_action = func(_action: String) -> void: pass
	viewport.add_child(preview)
	preview.set_process(false)
	preview.set_physics_process(false)
	var recovery := _redo_button(preview.overlay,"Recover turn request")
	_check(preview.mode == "complete" and recovery != null,"Cold completed card displays its recovery action")
	_check(not preview.story_boundary_ready(true) and not await cold.owner.continue_current(),"Held redo blocks Story dialogue and Continue on the completed card")
	if recovery != null:
		recovery.pressed.emit()
		await process_frame
		var screen: CanvasLayer = preview._redo_screen
		_check(is_instance_valid(screen) and preview.mode == "redo_requests" and not preview.running,"Visible completed-card button opens the existing recovery screen")
		if is_instance_valid(screen):
			var retry := _redo_button(screen,"Retry request")
			_check(retry != null and _redo_button(screen,"Redo my turn") == null and _redo_button(screen,"Request redo") == null,"Completed recovery offers retry without fresh consent")
			var calls: int = c.h.calls.size()
			if retry != null:
				retry.pressed.emit()
				for i in range(8): await process_frame
			_check(not client.held() and _only_gets(c.h.calls.slice(calls)) and c.h.receipts.size() == (1 if accepted else 0),"Visible retry settles the exact old operation with reads only")
			screen.close()
			await process_frame
			_check(preview.mode == "complete" and not preview.running and cold.online.last_room() == c.anchor,"Closing recovery returns to completion without recording or room changes")
			_check(_redo_button(preview.overlay,"Recover turn request") == null and _redo_button(preview.overlay,"Turn requests") == null and _redo_button(preview.overlay,"Request redo") == null,"Completed source without a hold has no useless turn-request action")
			preview._open_campaign_redo()
			_check(not is_instance_valid(preview._redo_screen),"Direct completed-card entry cannot start a new request after recovery")
	viewport.queue_free()
	await process_frame
	await process_frame
	c.h.free()

func _redo_button(node: Node, text: String) -> Button:
	for button: Button in node.find_children("*","Button",true,false):
		if button.text == text: return button
	return null

func _wire_and_capability() -> void:
	var wire := _json("res://tests/fixtures/campaign/redo-v1.json")
	var operation := {"source":wire.accept.source,"body":wire.accept,"stage_id":"upper-path","checkpoint_hash":wire.response.receipt.checkpoint_hash}
	_check(Canonical.same(StoryRedo.fork_body(operation),wire.fork_body) and StoryRedo.receipt_valid(wire.response.receipt,operation),"Parent accept hashes exactly the unchanged child fork body")
	for field: String in ["accepted_revision","branch","stage_index","stage_id","checkpoint_hash","request_hash","idempotency_key","operation","turn_id","pair_id"]:
		var changed: Dictionary = wire.response.receipt.duplicate(true)
		changed[field] = "wrong"
		_check(not StoryRedo.receipt_valid(changed,operation),"Wrong fork receipt field is rejected: "+field)
	for field: String in ["schema_version","accepted_revision","branch","stage_index"]:
		for invalid: Variant in ["wrong",true,0.5,-1,9007199254740992,{},[]]:
			var changed: Dictionary = wire.response.receipt.duplicate(true)
			changed[field] = invalid
			_check(not StoryRedo.receipt_valid(changed,operation),"Malformed numeric receipt field fails without throwing: "+field)
	for field: String in ["room_id","idempotency_key","request_hash","operation","stage_id","checkpoint_hash"]:
		for invalid: Variant in [7,true,null,{},[]]:
			var changed: Dictionary = wire.response.receipt.duplicate(true)
			changed[field] = invalid
			_check(not StoryRedo.receipt_valid(changed,operation),"Malformed string receipt field fails without throwing: "+field)
	for field: String in ["turn_id","recording_hash","pair_id"]:
		var changed: Dictionary = wire.response.receipt.duplicate(true)
		changed.erase(field)
		changed["unknown"] = null
		_check(not StoryRedo.receipt_valid(changed,operation),"An unknown field cannot replace a required null receipt field: "+field)
	var caps := Boundaries.campaign_capabilities(fixture.definition)
	_check(Capabilities.read(caps,[fixture.definition]).valid and not Capabilities.supports_redo(caps,[fixture.definition]),"Old capability remains valid and does not expose Story redo")
	caps["campaign_redo_version"] = 1
	_check(Capabilities.supports_redo(caps,[fixture.definition]),"Only explicit supported capability exposes the new action")
	caps["campaign_redo_version"] = true
	_check(not Capabilities.supports_redo(caps,[fixture.definition]),"Boolean is not a redo protocol version")
