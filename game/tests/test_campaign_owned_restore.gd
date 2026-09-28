extends "res://tests/test_campaign_online_session.gd"

class RestoreStore:
	extends Boundaries.MemoryStore
	var on_load: Callable
	func load_scope(scope: String) -> Dictionary:
		var result := super.load_scope(scope)
		if on_load.is_valid(): on_load.call(scope)
		return result

class RestoreHarness:
	extends Boundaries.Harness
	var operation_reply: Dictionary = {}
	func request_json(method: int, path: String, body: Dictionary = {}) -> Dictionary:
		if "/operations/" not in path: return await super.request_json(method,path,body)
		busy = true
		calls.append({"method":method,"path":path,"body":body.duplicate(true)})
		await get_tree().process_frame
		busy = false
		return operation_reply.duplicate(true) if not operation_reply.is_empty() else {"ok":false,"status":404,"code":"operation_not_found"}

func _run() -> void:
	fixture = _json("res://tests/fixtures/campaign/control-v2.json")
	await _same_current_pending(false)
	await _same_current_pending(true)
	await _late_b("continuing")
	await _late_b("advanced")
	await _terminal_restore(false)
	await _terminal_restore(true)
	await _guest_pending()
	await _historical_unknown()
	await _draft_restore()
	await _warm_live_draft_restore()
	await _warm_draft_restore_holds()
	await _restore_holds()
	print("Campaign owned-room restoration: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)

func _make(guest: bool = false) -> Dictionary:
	var h := RestoreHarness.new()
	h.store = RestoreStore.new()
	root.add_child(h)
	h.view = fixture.active_view.duplicate(true)
	if guest:
		h.player_id = GUEST
		h.identity_value.player_id = GUEST
		h.view.player_slot = "p1"
		h.view.invite_code = null
		h.view.invite_expires_at = null
	var anchor: String = h.view.campaign_room_id
	var target: String = fixture.accepted_result.campaign.chapters[1].room_id
	h.rooms[anchor] = _room("high-and-low",anchor,false)
	h.rooms[target] = _room("rolling-home",target,false)
	if guest:
		for room: Dictionary in h.rooms.values():
			room.player_slot = "p1"
			room.erase("invite_code")
	var online := Online.new(h,h.identity,h.store)
	_check(await online.open_room(anchor),"Current cache is verified by the real native engine")
	online.capabilities = {"mutations_enabled":true}
	var owner := Owner.new(online,h.identity,[fixture.definition],h.leave_ready,h.store)
	_check(owner.restore_owner() and owner.bind_campaign(anchor,Protocol.key(fixture.definition)),"The campaign owner is durable")
	_check(await owner.refresh() and await owner.select_current() and owner.adopt_selected(),"A real selected child is adopted before restart")
	return {"h":h,"online":online,"owner":owner,"anchor":anchor,"target":target}

func _cold(c: Dictionary) -> Dictionary:
	var online := Online.new(c.h,c.h.identity,c.h.store)
	var owner := Owner.new(online,c.h.identity,[fixture.definition],c.h.leave_ready,c.h.store)
	_check(owner.restore_owner(),"Cold campaign restoration reads its saved owner")
	online.capabilities = {"mutations_enabled":true}
	return {"online":online,"owner":owner}

func _same_current_pending(prior_leave_guard: bool) -> void:
	var c := await _make()
	var record := _json("res://tests/fixtures/cooperative/upper-path-a.json")
	_check(not await c.online.coordinator.commit(record) and not c.online.coordinator.pending().is_empty(),"A lost A response leaves a valid pending request")
	var cold := _cold(c)
	if prior_leave_guard: _check(not cold.owner.can_leave(),"An earlier leave check may load the same pending coordinator")
	var previous: RefCounted = cold.online.coordinator
	var before: Dictionary = c.h.store.saved.duplicate(true)
	var calls: int = c.h.calls.size()
	var writes: int = c.h.store.writes.size()
	_check(cold.owner.restore_selected_room(),"Cold entry restores exactly the already-selected pending child")
	_check(not cold.online.coordinator.pending().is_empty() and not cold.online.coordinator.read_only,"Pending recovery remains usable without weakening native admission")
	_check(cold.online.last_room() == c.anchor and cold.owner.selected_room() == c.anchor and Canonical.same(before,c.h.store.saved),"Restoration preserves all room, owner, index and pending bytes")
	_check(c.h.calls.size() == calls and c.h.store.writes.size() == writes,"Restoration itself performs no HTTP or local write")
	if previous != null:
		_check(previous.snapshot().is_empty() and previous.create_live_simulation() == null and not await previous.reconcile(),"A retained old coordinator is synchronously retired before replacement")
		_check(c.h.calls.size() == calls,"Stale callbacks cannot dispatch through the retired coordinator")
	_check(not cold.owner.can_leave() and not cold.owner.release_for_ordinary(),"A restored pending turn still blocks ordinary departure")
	var pending: Dictionary = cold.online.coordinator.pending()
	_check(not await cold.online.coordinator.reconcile(),"Unknown acceptance remains pending after deliberate recovery")
	_check(c.h.calls.size() == calls+2 and c.h.calls[calls].method == HTTPClient.METHOD_GET and c.h.calls[-1].method == HTTPClient.METHOD_POST and Canonical.same(c.h.calls[-1].body,pending.body),"Known missing receipt retries only the original exact saved POST")
	c.h.free()

func _prepare_b(c: Dictionary, chapter: String = "high-and-low", room_id: String = "") -> Dictionary:
	var room: Dictionary = c.h.rooms[c.anchor if room_id.is_empty() else room_id].duplicate(true)
	var level := Registry.definition(chapter+"@1")
	room.revision = 4
	room.stage_index = 1
	room.stage_id = level.stages[1].id
	room.checkpoint = _json("res://tests/fixtures/cooperative/"+level.stages[0].id+"-checkpoint.json")
	room.completed_pair_ids = ["p0-0"]
	room.recording_a = _json("res://tests/fixtures/cooperative/"+level.stages[1].id+"-a.json")
	room.a_turn_id = "t0-1-a"
	room.active_role = "b"
	room.first_player_id = GUEST
	room.active_player_id = HOST
	return room

func _late_b(phase: String) -> void:
	var c := await _make()
	c.h.rooms[c.anchor] = _prepare_b(c)
	_check(await c.online.coordinator.refresh(),"Native stage-two A proof admits the host's final B turn")
	_check(not await c.online.coordinator.commit(_json("res://tests/fixtures/cooperative/down-and-around-b.json")),"Lost final B response is saved before campaign progress")
	var pending: Dictionary = c.online.coordinator.pending()
	_check(not pending.is_empty() and pending.body.checkpoint.stage_index == 2,"The saved B includes its actual derived final checkpoint")
	var complete := _room("high-and-low",c.anchor,true)
	complete.revision = 5
	c.h.rooms[c.anchor] = complete
	c.h.view = fixture.pending_result.campaign.duplicate(true) if phase == "continuing" else fixture.accepted_result.campaign.duplicate(true)
	_check(await c.owner.refresh(),"A friend's "+phase+" publication can arrive before our B receipt")
	var cold := _cold(c)
	var before: Dictionary = c.h.store.saved.duplicate(true)
	var calls: int = c.h.calls.size()
	_check(cold.owner.restore_selected_room() and cold.online.coordinator.campaign_recovery_only(),"The exact previously selected source restores for recovery after "+phase)
	_check(Canonical.same(before,c.h.store.saved) and c.h.calls.size() == calls,"Historical restoration does not select the new child or replay the POST")
	c.h.operation_reply = {"ok":true,"status":200,"data":_b_receipt(pending,complete)}
	_check(await cold.online.coordinator.reconcile() and cold.online.coordinator.pending().is_empty(),"A late accepted B receipt settles through the existing native verifier")
	_check(c.h.calls.size() == calls+1 and c.h.calls[-1].method == HTTPClient.METHOD_GET,"An accepted historical B needs only its receipt GET")
	_check(cold.online.coordinator.chapter_complete() and cold.owner.selected_room() == c.anchor and cold.online.last_room() == c.anchor,"The completed source remains owned until deliberate handoff")
	_check(cold.online.coordinator.create_live_simulation() == null and not await cold.online.coordinator.fork(0),"Recovery-only source cannot create new input or fork")
	if phase == "advanced":
		_check(await cold.owner.select_current() and cold.owner.adopt_selected(),"After receipt settlement, the ordinary verified handoff can proceed")
		_check(cold.online.last_room() == c.target and not cold.online.coordinator.campaign_recovery_only(),"Only separately admitted current target regains normal play")
	c.h.free()

func _b_receipt(pending: Dictionary, room: Dictionary) -> Dictionary:
	var body: Dictionary = pending.body
	return {"receipt":{"schema_version":2,"room_id":room.room_id,"idempotency_key":body.idempotency_key,
		"request_hash":pending.request_hash,"operation":"turns","accepted_revision":5,"branch":0,"stage_index":1,
		"stage_id":body.recording.stage_id,"turn_id":"t0-1-b","recording_hash":body.recording.recording_hash,
		"pair_id":"p0-1","checkpoint_hash":body.checkpoint.checkpoint_hash},"room":room.duplicate(true)}

func _terminal_restore(with_pending: bool) -> void:
	var c := await _make()
	c.h.view = fixture.accepted_result.campaign.duplicate(true)
	_check(await c.owner.refresh() and await c.owner.select_current() and c.owner.adopt_selected(),"Terminal fixture owns the actual final chapter")
	var pending := {}
	if with_pending:
		c.h.rooms[c.target] = _prepare_b(c,"rolling-home",c.target)
		_check(await c.online.coordinator.refresh(),"Final chapter's native A proof admits its B")
		_check(not await c.online.coordinator.commit(_json("res://tests/fixtures/cooperative/bring-it-home-b.json")),"Final chapter B has a lost response")
		pending = c.online.coordinator.pending()
	var complete := _room("rolling-home",c.target,true)
	complete.revision = 5
	c.h.rooms[c.target] = complete
	c.h.view.state = "complete"
	c.h.view.revision = 6
	c.h.view.chapters[1].completion = {"source_revision":5,"source_branch":0,"checkpoint_hash":complete.checkpoint.checkpoint_hash,
		"transition_id":"d".repeat(64),"from_campaign_revision":4,"accepted_campaign_revision":6}
	_check(await c.owner.refresh(),"Final Finish publication arrives before the cached scene catches up")
	var cold := _cold(c)
	_check(cold.owner.restore_selected_room() and cold.online.coordinator.campaign_recovery_only(),"Terminal current index is restored with recovery-only capability")
	var calls: int = c.h.calls.size()
	_check(cold.online.coordinator.create_live_simulation() == null and not cold.online.coordinator.save_draft({}) and not await cold.online.coordinator.fork(0),"Even a clear older terminal cache cannot start new input or fork")
	_check(c.h.calls.size() == calls,"Terminal input refusal does not dispatch")
	if with_pending:
		c.h.operation_reply = {"ok":true,"status":200,"data":_b_receipt(pending,complete)}
		_check(await cold.online.coordinator.reconcile() and cold.online.coordinator.chapter_complete(),"Late final B settles into the real terminal world")
		_check(c.h.calls.size() == calls+1 and c.h.calls[-1].method == HTTPClient.METHOD_GET,"Terminal B acceptance also uses only its receipt GET")
	c.h.free()

func _guest_pending() -> void:
	var c := await _make(true)
	var room: Dictionary = c.h.rooms[c.anchor]
	room.revision = 2
	room.recording_a = _json("res://tests/fixtures/cooperative/upper-path-a.json")
	room.a_turn_id = "t0-0-a"
	room.active_role = "b"
	room.active_player_id = GUEST
	_check(await c.online.coordinator.refresh(),"Guest reads the actual host A proof")
	_check(not await c.online.coordinator.commit(_json("res://tests/fixtures/cooperative/upper-path-b.json")),"Guest B persists before its lost response")
	var cold := _cold(c)
	var before: Dictionary = c.h.store.saved.duplicate(true)
	var calls: int = c.h.calls.size()
	_check(cold.owner.restore_selected_room() and cold.online.coordinator.snapshot().player_slot == "p1","Guest restores the same owned child with its p1 projection")
	_check(not cold.online.coordinator.pending().is_empty() and Canonical.same(before,c.h.store.saved) and c.h.calls.size() == calls,"Guest's pending B and every journal byte remain intact")
	c.h.free()

func _historical_unknown() -> void:
	var c := await _make()
	await c.online.coordinator.commit(_json("res://tests/fixtures/cooperative/upper-path-a.json"))
	c.h.view = fixture.accepted_result.campaign.duplicate(true)
	_check(await c.owner.refresh(),"Later publication coexists with unresolved earlier A")
	var cold := _cold(c)
	_check(cold.owner.restore_selected_room() and cold.online.coordinator.campaign_recovery_only(),"Historical unknown request restores without fresh gameplay permission")
	var pending: Dictionary = cold.online.coordinator.pending()
	var calls: int = c.h.calls.size()
	var changed: Dictionary = pending.body.duplicate(true)
	changed.idempotency_key = "different-key-retained"
	var denied: Dictionary = await cold.online.coordinator._request(HTTPClient.METHOD_POST,"/v2/rooms/"+c.anchor+"/turns",changed)
	_check(not denied.ok and c.h.calls.size() == calls,"Historical capability rejects even a direct changed request body")
	_check(not await cold.online.coordinator.reconcile() and c.h.calls.size() == calls+2,"Known absent receipt permits exactly the existing saved retry")
	_check(Canonical.same(c.h.calls[-1].body,pending.body) and not cold.online.coordinator.pending().is_empty(),"Uncertain saved retry preserves its original key and proof")
	c.h.free()

func _draft_restore() -> void:
	var c := await _make()
	var record := _json("res://tests/fixtures/cooperative/upper-path-a.json")
	_check(c.online.coordinator.save_draft(record),"A real saved rehearsal exists before exit")
	var cold := _cold(c)
	var before: Dictionary = c.h.store.saved.duplicate(true)
	_check(cold.owner.restore_selected_room() and Canonical.same(cold.online.coordinator.draft(),record),"Same-current restore native-validates and retains the saved rehearsal")
	_check(not cold.online.coordinator.campaign_recovery_only() and Canonical.same(before,c.h.store.saved),"Current active restore preserves resume permission without rewriting the draft")
	c.h.free()

func _warm_live_draft_restore() -> void:
	for guest: bool in [false,true]:
		var c := await _make(guest)
		if guest:
			var room: Dictionary = c.h.rooms[c.anchor]
			room.revision = 2
			room.recording_a = _json("res://tests/fixtures/cooperative/upper-path-a.json")
			room.a_turn_id = "t0-0-a"
			room.active_role = "b"
			room.active_player_id = GUEST
			_check(await c.online.coordinator.refresh(),"Warm guest rehearsal starts with the host's accepted A")
		var source: RefCounted = c.online.coordinator
		var live: RefCounted = source.create_live_simulation()
		_check(live != null,"Selected child creates a real warm rehearsal")
		if live == null:
			c.h.free()
			continue
		for tick in range(1200 if guest else 30):
			if live.finished: break
			live.step()
		if guest: _check(live.finished and not live.snapshot().get("can_commit",false),"Guest rehearsal expires without completing a turn")
		var record: Dictionary = live.export_recording()
		var room_before: Dictionary = source.snapshot()
		_check(source.save_live_draft(live),"The registered live rehearsal is saved before returning to Story")
		# Do not call draft() here: that would verify it and hide the warm Resume bug.
		_check(not source.observe_campaign_state().draft_ready and c.online.capture_campaign_restore_lease(c.anchor).is_empty(),"Pure restore observation leaves the live-saved draft unverified")
		var before: Dictionary = c.h.store.saved.duplicate(true)
		var calls: int = c.h.calls.size()
		var writes: int = c.h.store.writes.size()
		var restored: bool = c.owner.restore_selected_room()
		_check(restored,"Warm Story Resume restores a live-saved rehearsal without a cold owner or prior draft read")
		_check(Canonical.same(before,c.h.store.saved) and c.h.calls.size() == calls and c.h.store.writes.size() == writes,"Warm Resume preserves every journal and performs no HTTP or local write")
		if restored:
			var current: RefCounted = c.online.coordinator
			_check(Canonical.same(current.draft(),record) and Canonical.same(current.snapshot(),room_before) and current.pending().is_empty(),"Restored rehearsal and accepted prior A remain exact without a submitted turn")
			_check(current.create_live_simulation(true) != null and current.create_live_simulation(false) != null,"Restored rehearsal still supports resume and a fresh retry engine")
			_check(Canonical.same(before,c.h.store.saved) and c.h.calls.size() == calls,"Preparing resume or retry does not discard the saved rehearsal")
		c.h.free()

func _warm_draft_restore_holds() -> void:
	for mode: String in ["corrupt_live","newer_draft"]:
		var c := await _make()
		var source: RefCounted = c.online.coordinator
		var live: RefCounted = source.create_live_simulation()
		live.step()
		if mode == "corrupt_live": live.get("_players")[live.active_slot].x += 80
		_check(source.save_live_draft(live),"Warm "+mode+" case enters only the structural live-save path")
		var expected: Array = [c.h.store.saved.duplicate(true)]
		var calls: int = c.h.calls.size()
		var writes: int = c.h.store.writes.size()
		if mode == "newer_draft":
			c.h.store.on_load = func(scope: String):
				if scope != _room_scope(c.anchor): return
				c.h.store.on_load = Callable()
				live.step()
				_check(source.save_live_draft(live),"A newer live draft arrives while the replacement reads the older cache")
				expected[0] = c.h.store.saved.duplicate(true)
		_check(not c.owner.restore_selected_room(),"Warm Resume rejects "+mode+" instead of adopting an unverified or stale replacement")
		_check(c.online.coordinator == source and c.online.last_room() == c.anchor and c.owner.selected_room() == c.anchor,"Held warm "+mode+" preserves its source coordinator and selection")
		_check(Canonical.same(c.h.store.saved,expected[0]) and c.h.calls.size() == calls and c.h.store.writes.size() == writes+(1 if mode == "newer_draft" else 0),"Held warm "+mode+" preserves exact evidence with no implicit request, rewrite or discard")
		if mode == "corrupt_live": _check(source.read_only,"Invalid warm rehearsal is held by native replay verification")
		c.h.store.on_load = Callable()
		c.h.free()

func _restore_holds() -> void:
	for mode: String in ["last_room","activation","deleting","cache","input","photo","identity","late_input"]:
		var c := await _make()
		if mode == "last_room": c.h.store.saved["relay-lobby-v2:"+HOST].last_room = c.target
		elif mode == "activation":
			var saved: Dictionary = c.h.store.saved[_journal(c.anchor)]
			saved.view = fixture.accepted_result.campaign.duplicate(true)
			saved.view.activation = {"transition_id":fixture.accepted_result.receipt.transition_id}
			saved.selected_room = c.target
			c.h.store.saved["relay-lobby-v2:"+HOST].last_room = c.target
		elif mode == "deleting": c.h.store.saved[_journal(c.anchor)].view.state = "deleting"
		elif mode == "cache": c.h.store.saved[_room_scope(c.anchor)].snapshot.checkpoint.checkpoint_hash = "f".repeat(64)
		elif mode == "input": c.h.leave_allowed = false
		elif mode == "photo": c.h.busy = true
		var cold := _cold(c)
		if mode in ["identity","late_input"]:
			c.h.store.on_load = func(scope: String):
				if scope == _room_scope(c.anchor):
					if mode == "identity": c.h.identity_value.epoch += 1
					else: c.h.leave_allowed = false
		var before: Dictionary = c.h.store.saved.duplicate(true)
		var calls: int = c.h.calls.size()
		_check(not cold.owner.restore_selected_room(),"Restoration respects "+mode+" authority/readiness")
		_check(cold.online.coordinator == null and Canonical.same(before,c.h.store.saved) and c.h.calls.size() == calls,"Held "+mode+" neither changes owner nor fetches/writes")
		c.h.store.on_load = Callable()
		c.h.free()
