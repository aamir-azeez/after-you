extends "res://tests/test_campaign_ordinary_guard.gd"

class ArchiveHarness:
	extends RestoreHarness
	var replies: Dictionary = {}
	func request_json(method: int, path: String, body: Dictionary = {}) -> Dictionary:
		if method != HTTPClient.METHOD_GET or not replies.has(path): return await super.request_json(method,path,body)
		busy = true
		calls.append({"method":method,"path":path,"body":body.duplicate(true)})
		if on_request.is_valid(): on_request.call()
		await get_tree().process_frame
		busy = false
		return replies[path].duplicate(true)

func _run() -> void:
	fixture = _json("res://tests/fixtures/campaign/control-v2.json")
	await _archived_pending_story()
	await _damaged_story_control()
	await _damaged_story_lobby()
	await _schema_one_ordinary_pending()
	await _unknown_replies_hold()
	await _classification_lifetime()
	print("Archived Story navigation: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)

func _story_fixture() -> Dictionary:
	var h := ArchiveHarness.new()
	h.store = RestoreStore.new()
	root.add_child(h)
	h.view = fixture.active_view.duplicate(true)
	var anchor: String = h.view.campaign_room_id
	var target: String = fixture.accepted_result.campaign.chapters[1].room_id
	h.rooms[anchor] = _room("high-and-low",anchor,false)
	h.rooms[target] = _room("rolling-home",target,false)
	var online := Online.new(h,h.identity,h.store)
	_check(await online.open_room(anchor),"Archived fixture starts with a native-verified room")
	online.capabilities = {"mutations_enabled":true}
	var owner := Owner.new(online,h.identity,[fixture.definition],h.leave_ready,h.store)
	_check(owner.restore_owner() and owner.bind_campaign(anchor,Protocol.key(fixture.definition)),"Archived fixture retains its original owner")
	_check(await owner.refresh() and await owner.select_current() and owner.adopt_selected(),"Archived fixture adopts its original Story child")
	return {"h":h,"online":online,"owner":owner,"anchor":anchor,"target":target}

func _ordinary_pending_fixture() -> Dictionary:
	var h := ArchiveHarness.new()
	h.store = RestoreStore.new()
	root.add_child(h)
	h.rooms[ORDINARY] = _room("high-and-low",ORDINARY,false)
	h.rooms[NEXT_ROOM] = _room("rolling-home",NEXT_ROOM,false)
	var online := Online.new(h,h.identity,h.store)
	_check(await online.open_room(ORDINARY),"Old ordinary fixture has a native-verified schema-one index")
	online.capabilities = {"mutations_enabled":true}
	_check(not await online.coordinator.commit(_json("res://tests/fixtures/cooperative/upper-path-a.json")) and not online.coordinator.pending().is_empty(),"Old ordinary fixture retains a real uncertain native turn")
	_check(h.store.saved["relay-lobby-v2:"+HOST].schema_version == 1,"Ordinary pending predates standalone_ids")
	h.store.saved["relay-campaign-lobby-v1:"+HOST] = {"future_version":99,"retained":"unchanged"}
	return {"h":h,"online":online}

func _archived(c: Dictionary) -> Dictionary:
	var online := Online.new(c.h,c.h.identity,c.h.store)
	var owner := Owner.new(online,c.h.identity,[fixture.definition],c.h.leave_ready,c.h.store)
	owner.archive_story_runtime()
	_check(owner.restore_owner(),"Archived Story restores only its classification index")
	online.capabilities = {"mutations_enabled":true}
	_check(owner._campaign == null and owner._bridge == null and owner._redo == null and owner._terminal == null,"No Story session, bridge, redo or terminal workflow is instantiated")
	return {"online":online,"owner":owner}

func _archived_pending_story() -> void:
	var c := await _story_fixture()
	_check(not await c.online.coordinator.commit(_json("res://tests/fixtures/cooperative/upper-path-a.json")) and not c.online.coordinator.pending().is_empty(),"Fixture has an uncertain Story turn saved before the update")
	var before: Dictionary = c.h.store.saved.duplicate(true)
	var count: int = c.h.calls.size()
	var cold := _archived(c)
	_check(cold.owner.ordinary_entry_allowed() and cold.online.can_leave_for_legacy(),"Archived Story does not hold ordinary rooms or earlier islands")
	_check(cold.online.coordinator == null and cold.online.pending_redo_room().is_empty(),"Story's saved room is never rebound as an ordinary recovery room")
	_check(not await cold.online.open_room(c.anchor),"Ordinary entry still refuses the archived Story room")
	_check(c.h.calls.size() == count and Canonical.same(before,c.h.store.saved),"Archive discovery sends no request and rewrites no saved data")
	c.h.rooms[ORDINARY] = _room("high-and-low",ORDINARY,false)
	_check(await cold.online.open_room(ORDINARY),"A native-verified standalone chapter opens beside archived Story data")
	_check(c.h.calls.size() == count+1 and c.h.calls.back().method == HTTPClient.METHOD_GET and c.h.calls.back().path == "/v2/rooms/"+ORDINARY,"Only the requested ordinary room is read")
	for scope: String in before:
		if scope != "relay-lobby-v2:"+HOST:
			_check(Canonical.same(before[scope],c.h.store.saved.get(scope)),"Archived scope remains intact: "+scope.get_slice(":",0))
	var factory: RefCounted = cold.online.auxiliary_context_factory()
	for purpose: String in ["presence","photo","replay","safety"]:
		_check(not factory.for_room(c.anchor,purpose).current(),"Archived Story cannot activate "+purpose+" transport")
		_check(factory.for_room(ORDINARY,purpose).current(),"Ordinary "+purpose+" context remains available")
	_check(not await cold.online.coordinator.commit(_json("res://tests/fixtures/cooperative/upper-path-a.json")),"An ordinary uncertain turn still uses its existing journal")
	var pending: Dictionary = cold.online.coordinator.pending()
	var next := _archived(c)
	count = c.h.calls.size()
	_check(not next.online.can_leave_for_legacy() and not await next.online.open_room(NEXT_ROOM),"Real ordinary pending turns retain their navigation lock")
	_check(c.h.calls.size() == count,"Ordinary pending protection dispatches nothing")
	_check(await next.online.open_room(ORDINARY) and Canonical.same(pending,next.online.coordinator.pending()),"The same ordinary room still recovers its original pending request")
	c.h.free()

func _damaged_story_control() -> void:
	var c := await _story_fixture()
	c.h.view = fixture.accepted_result.campaign.duplicate(true)
	_check(await c.owner.refresh() and await c.owner.select_current() and c.owner.adopt_selected(),"Fixture retains an actual later Story chapter as the last room")
	_check(not await c.online.coordinator.commit(_json("res://tests/fixtures/cooperative/weight-of-a-friend-a.json")) and not c.online.coordinator.pending().is_empty(),"Later Story chapter has an unresolved turn before its metadata is damaged")
	# The valid lobby identifies the anchor even when its optional Story
	# control/terminal files are unusable. They are retained for future repair.
	c.h.store.saved["relay-campaign-v1:"+HOST+":"+c.anchor] = {"future_version":99}
	var before: Dictionary = c.h.store.saved.duplicate(true)
	var count: int = c.h.calls.size()
	var cold := _archived(c)
	_check(cold.owner.classify_room(c.anchor).campaign and not cold.online.can_leave_for_legacy(),"Known anchor does not misclassify its unknown later selection")
	_check(c.h.calls.size() == count and Canonical.same(before,c.h.store.saved),"Damaged files are neither interpreted as gameplay nor repaired implicitly")
	c.h.replies["/v2/rooms/"+c.target] = {"ok":false,"status":409,"code":"campaign_client_required"}
	_check(await cold.online.prepare_archived_navigation() and cold.online.can_leave_for_legacy(),"Only the exact ordinary-GET Story boundary permits quarantine of the later child")
	_check(c.h.calls.size() == count+1 and c.h.calls.back().method == HTTPClient.METHOD_GET and c.h.calls.back().path == "/v2/rooms/"+c.target,"Classification reads the old child once without replaying its pending POST")
	_check(cold.online.coordinator == null and Canonical.same(before,c.h.store.saved),"Positively identified Story keeps its pending cache untouched and unbound")
	_check(cold.owner.classify_room(c.target).campaign and cold.owner.auxiliary_room_binding(c.target).kind == "held","The same evidence closes old Story replay and media entry")
	c.h.rooms[ORDINARY] = _room("high-and-low",ORDINARY,false)
	_check(await cold.online.open_room(ORDINARY),"Ordinary chapter admission stays usable with a damaged archived Story control file")
	_check(Canonical.same(before["relay-campaign-v1:"+HOST+":"+c.anchor],c.h.store.saved["relay-campaign-v1:"+HOST+":"+c.anchor]),"Opening the chapter preserves the damaged Story file")
	c.h.free()

func _damaged_story_lobby() -> void:
	var c := await _story_fixture()
	c.h.view = fixture.accepted_result.campaign.duplicate(true)
	_check(await c.owner.refresh() and await c.owner.select_current() and c.owner.adopt_selected(),"Malformed-index fixture selects its later Story chapter")
	var scope := "relay-campaign-lobby-v1:"+HOST
	c.h.store.saved[scope] = {"future_version":99,"retained":"unchanged"}
	var before: Dictionary = c.h.store.saved.duplicate(true)
	var calls: int = c.h.calls.size()
	var cold := _archived(c)
	_check(cold.owner.ordinary_entry_allowed() and not cold.online.can_leave_for_legacy() and cold.online.coordinator == null,"An unreadable Story index cannot silently discard an unclassified old selection")
	_check(not cold.owner.classify_room(c.target).complete and cold.owner.auxiliary_room_binding(c.target).kind == "held","Unknown archived rooms have no media authority")
	_check(Canonical.same(before,c.h.store.saved) and calls == c.h.calls.size(),"Unknown saved state is quarantined without writes or requests")
	c.h.replies["/v2/rooms/"+c.target] = {"ok":false,"status":409,"code":"campaign_client_required"}
	_check(await cold.online.prepare_archived_navigation() and cold.online.can_leave_for_legacy(),"An authenticated Story boundary resolves the old selection despite a malformed index")
	_check(calls+1 == c.h.calls.size() and Canonical.same(before,c.h.store.saved),"Malformed-index classification is one read with no save changes")
	c.h.rooms[ORDINARY] = _room("high-and-low",ORDINARY,false)
	_check(await cold.online.open_room(ORDINARY),"Independent server-verified ordinary ownership works beside an unreadable Story index")
	for key: String in before:
		if key != "relay-lobby-v2:"+HOST:
			_check(Canonical.same(before[key],c.h.store.saved.get(key)),"Malformed-index escape preserves saved scope: "+key.get_slice(":",0))
	_check(not await cold.online.coordinator.commit(_json("res://tests/fixtures/cooperative/upper-path-a.json")),"Ordinary fixture retains its own uncertain turn")
	var again := _archived(c)
	calls = c.h.calls.size()
	_check(not again.online.can_leave_for_legacy() and not await again.online.open_room(NEXT_ROOM),"Malformed Story cannot bypass a proven ordinary pending-turn lock")
	_check(calls == c.h.calls.size(),"Ordinary recovery lock remains local")
	c.h.free()

func _schema_one_ordinary_pending() -> void:
	var c := await _ordinary_pending_fixture()
	var pending: Dictionary = c.online.coordinator.pending()
	var before: Dictionary = c.h.store.saved.duplicate(true)
	var count: int = c.h.calls.size()
	var cold := _archived(c)
	_check(not cold.online.can_leave_for_legacy() and not await cold.online.open_room(NEXT_ROOM),"Missing standalone_ids cannot release the old ordinary pending request")
	_check(cold.online.coordinator == null and c.h.calls.size() == count,"Unknown previous room is held before loading its cache or reading another target")
	_check(await cold.online.prepare_archived_navigation(),"A native-valid ordinary GET classifies the old schema-one selection")
	_check(c.h.calls.size() == count+1 and c.h.calls.back().method == HTTPClient.METHOD_GET and c.h.calls.back().path == "/v2/rooms/"+ORDINARY,"Classification sends exactly one old-room GET and no pending POST")
	_check(cold.online.coordinator != null and Canonical.same(pending,cold.online.coordinator.pending()) and not cold.online.coordinator.campaign_recovery_only(),"Ordinary classification restores the exact pending journal with ordinary recovery authority")
	_check(Canonical.same(before,c.h.store.saved),"Positive ordinary classification performs no index or room-cache write")
	count = c.h.calls.size()
	_check(not cold.online.can_leave_for_legacy() and not await cold.online.open_room(NEXT_ROOM),"Restored ordinary pending still blocks a different room")
	_check(c.h.calls.size() == count and Canonical.same(before,c.h.store.saved),"Departure cannot resend or erase the pending turn")
	_check(await cold.online.open_room(ORDINARY) and Canonical.same(pending,cold.online.coordinator.pending()),"Opening the same ordinary room retains its recovery request")
	cold.online.invalidate_identity()
	_check(cold.online.archived_room_kind(ORDINARY).is_empty(),"Invalidating identity discards in-memory classification evidence")
	c.h.free()

func _unknown_replies_hold() -> void:
	for failure: String in ["offline","timeout","forbidden","missing","server","other409","wrong_room","wrong_proof"]:
		var c := await _ordinary_pending_fixture()
		var response := {"ok":false,"status":0,"code":"connection_interrupted"}
		match failure:
			"timeout": response.code = "request_timeout"
			"forbidden": response = {"ok":false,"status":403,"code":"player_blocked"}
			"missing": response = {"ok":false,"status":404,"code":"room_not_found"}
			"server": response = {"ok":false,"status":503,"code":"service_unavailable"}
			"other409": response = {"ok":false,"status":409,"code":"campaign_required"}
			"wrong_room","wrong_proof":
				var room: Dictionary = c.h.rooms[ORDINARY].duplicate(true)
				if failure == "wrong_room": room.room_id = NEXT_ROOM
				else: room.checkpoint.checkpoint_hash = "a".repeat(64)
				response = {"ok":true,"status":200,"data":room}
		c.h.replies["/v2/rooms/"+ORDINARY] = response
		var before: Dictionary = c.h.store.saved.duplicate(true)
		var count: int = c.h.calls.size()
		var cold := _archived(c)
		_check(not await cold.online.prepare_archived_navigation(),failure+" cannot establish Story or ordinary ownership")
		_check(c.h.calls.size() == count+1 and c.h.calls.back().method == HTTPClient.METHOD_GET and c.h.calls.back().path == "/v2/rooms/"+ORDINARY,"Unresolved classification reads only the previous room")
		_check(cold.online.coordinator == null and cold.online.archived_room_kind(ORDINARY).is_empty() and Canonical.same(before,c.h.store.saved),failure+" preserves unbound cache, pending turn and old selection")
		_check(not cold.online.can_leave_for_legacy() and not await cold.online.open_room(NEXT_ROOM) and c.h.calls.size() == count+1,"Unknown classification cannot release pending ownership or probe a different room")
		c.h.free()

func _classification_lifetime() -> void:
	for change: String in ["epoch","device","backend","selection"]:
		var c := await _ordinary_pending_fixture()
		var cold := _archived(c)
		var before: Dictionary = c.h.store.saved.duplicate(true)
		c.h.on_request = func():
			match change:
				"epoch": c.h.identity_value.epoch += 1
				"device": c.h.device_token = "synthetic-replacement-device"
				"backend": c.h.base_url = "https://replacement.synthetic.invalid"
				"selection": cold.online._room_selection_generation += 1
		_check(not await cold.online.prepare_archived_navigation(),"Changed "+change+" rejects a delayed old-room classification")
		_check(cold.online.archived_room_kind(ORDINARY).is_empty() and Canonical.same(before,c.h.store.saved),"A stale "+change+" response cannot establish evidence or change saved state")
		c.h.on_request = Callable()
		c.h.free()
