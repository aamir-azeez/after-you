extends "res://tests/test_archived_story_rooms.gd"
## A last room the server no longer has (closed, left or removed) while this
## phone still holds a turn whose reply was lost. Only a definitive gone answer
## to the one checked read releases it; the turn's journal stays as it was.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const GONE := {
	"missing": {"ok":false,"status":404,"code":"room_not_found"},
	"closed": {"ok":false,"status":410,"code":"room_closed"},
	"deleted": {"ok":false,"status":410,"code":"room_deleted"},
}
const UNCERTAIN := {
	"timeout": {"ok":false,"status":0,"code":"request_timeout"},
	"offline": {"ok":false,"status":0,"code":"connection_interrupted"},
	"outage": {"ok":false,"status":503,"code":"service_unavailable"},
	"gateway": {"ok":false,"status":504,"code":"gateway_timeout"},
	"other404": {"ok":false,"status":404,"code":"not_found"},
	"other410": {"ok":false,"status":410,"code":"invite_expired"},
	"blocked": {"ok":false,"status":403,"code":"player_blocked"},
	"ignored": {"ok":false,"ignored":true,"status":404,"code":"room_not_found"},
}

func _run() -> void:
	for answer: String in GONE: await _gone_turn(answer)
	for answer: String in UNCERTAIN: await _uncertain_turn(answer)
	await _race_during_check()
	await _late_reply()
	await _note_survives_backgrounding()
	await _two_phones()
	await _story_room_left_lists()
	for gone: bool in [false,true]: await _read_proof_follows_list(gone)
	print("Gone room release: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)

func _index_scope() -> String: return "relay-lobby-v2:"+HOST

## Every saved scope except the lobby index, as bytes.
func _journals(store: RefCounted) -> PackedByteArray:
	return _journals_of(store.saved)

func _journals_of(saved: Dictionary) -> PackedByteArray:
	var kept: Dictionary = saved.duplicate(true)
	kept.erase(_index_scope())
	return var_to_bytes(kept)

func _room_bytes(store: RefCounted, room_id: String) -> PackedByteArray:
	return var_to_bytes(store.saved.get(_room_scope(room_id)))

func _gone_turn(answer: String) -> void:
	var c := await _unproven_last_room(ORDINARY,"high-and-low")
	c.h.replies["/v2/rooms/"+ORDINARY] = GONE[answer]
	var online := _cold(c)
	var journals := _journals(c.h.store)
	var room_bytes := _room_bytes(c.h.store,ORDINARY)
	var count: int = c.h.calls.size()
	_check(not await online.open_room(NEXT_ROOM) and c.h.calls.size() == count,answer+": the held turn blocks other rooms before the check")
	_check(await online.prepare_archived_navigation(),answer+": the check releases the room")
	_check(c.h.calls.size() == count+1 and c.h.calls.back().method == HTTPClient.METHOD_GET and c.h.calls.back().path == "/v2/rooms/"+ORDINARY,answer+": one GET, and the turn is never sent")
	_check(online.last_room().is_empty() and online.coordinator == null and online.last_error.is_empty(),answer+": the gone room is no longer the last room")
	_check(online.take_released_room_note() == PlayerCopy.ROOMS_API_A7ACF38988EE and online.take_released_room_note().is_empty(),answer+": the player is told once that the room was closed")
	_check(_journals(c.h.store) == journals and not c.h.store.saved[_room_scope(ORDINARY)].pending.is_empty(),answer+": the turn's journal keeps its exact bytes")
	_check(online.can_leave_for_legacy() and await online.open_room(NEXT_ROOM) and online.last_room() == NEXT_ROOM,answer+": other rooms open again")
	_check(_room_bytes(c.h.store,ORDINARY) == room_bytes,answer+": opening another room leaves the old journal alone")
	c.h.free()

func _uncertain_turn(answer: String) -> void:
	var c := await _unproven_last_room(ORDINARY,"high-and-low")
	c.h.replies["/v2/rooms/"+ORDINARY] = UNCERTAIN[answer]
	var online := _cold(c)
	var before: Dictionary = c.h.store.saved.duplicate(true)
	var count: int = c.h.calls.size()
	_check(not await online.prepare_archived_navigation(),answer+": an answer that is not a definitive gone keeps the hold")
	_check(online.last_room() == ORDINARY and online.take_released_room_note().is_empty() and Canonical.same(before,c.h.store.saved),answer+": nothing is released or written")
	_check(not await online.open_room(NEXT_ROOM) and c.h.calls.size() == count+1,answer+": other rooms stay held, as today")
	# The retry that follows still works once the server answers.
	c.h.replies.erase("/v2/rooms/"+ORDINARY)
	_check(await online.prepare_archived_navigation() and online.coordinator != null and not online.coordinator.pending().is_empty(),answer+": a later check of the live room restores its held turn")
	c.h.free()

## Taps and identity changes while the check's read is out.
func _race_during_check() -> void:
	var c := await _unproven_last_room(ORDINARY,"high-and-low")
	c.h.replies["/v2/rooms/"+ORDINARY] = GONE.missing
	var online := _cold(c)
	var journals := _journals(c.h.store)
	var taps := [{"done":false,"value":true},{"done":false,"value":true},{"done":false,"value":true}]
	c.h.on_request = func() -> void:
		c.h.on_request = Callable()
		_check(online.busy(),"The session is busy while the check is out")
		_open_into(online,ORDINARY,taps[0])
		_open_into(online,NEXT_ROOM,taps[1])
		_prepare_into(online,taps[2])
	var count: int = c.h.calls.size()
	_check(await online.prepare_archived_navigation() and online.last_room().is_empty(),"The check still releases the room")
	_check(taps.all(func(tap: Dictionary) -> bool: return tap.done and not tap.value),"A retry, an open or a second check tapped during it is refused")
	_check(c.h.calls.size() == count+1 and _journals(c.h.store) == journals,"Nothing else was sent or written")
	_check(await online.open_room(NEXT_ROOM),"Other rooms open after it")
	c.h.free()
	# A new identity while the read is out: its answer settles nothing.
	c = await _unproven_last_room(ORDINARY,"high-and-low")
	c.h.replies["/v2/rooms/"+ORDINARY] = GONE.missing
	online = _cold(c)
	var before: Dictionary = c.h.store.saved.duplicate(true)
	c.h.on_request = func() -> void:
		c.h.on_request = Callable()
		c.h.identity_value.epoch += 1
	_check(not await online.prepare_archived_navigation() and Canonical.same(before,c.h.store.saved),"A gone answer for a replaced identity releases and writes nothing")
	_check(online.take_released_room_note().is_empty(),"It leaves no note")
	_check(await online.prepare_archived_navigation() and online.last_room().is_empty() and _journals(c.h.store) == _journals_of(before),"The current identity's own check then releases it")
	c.h.free()

func _open_into(online: RefCounted, room_id: String, result: Dictionary) -> void:
	result.value = await online.open_room(room_id)
	result.done = true

func _prepare_into(online: RefCounted, result: Dictionary) -> void:
	result.value = await online.prepare_archived_navigation()
	result.done = true

## A coordinator bound to the room when it was released can neither send nor
## save afterwards: its late answers change nothing.
func _late_reply() -> void:
	var h := ArchiveHarness.new()
	root.add_child(h)
	h.rooms[ORDINARY] = _room("high-and-low",ORDINARY,false)
	h.rooms[NEXT_ROOM] = _room("rolling-home",NEXT_ROOM,false)
	var first := Online.new(h,h.identity,h.store)
	_check(await first.open_room(NEXT_ROOM) and await first.open_room(ORDINARY),"Both rooms were opened")
	first.capabilities = {"mutations_enabled":true}
	_check(not await first.coordinator.commit(_json("res://tests/fixtures/cooperative/upper-path-a.json")) and not first.coordinator.pending().is_empty(),"The turn's reply is lost")
	# A later start restores the room from its saved proof alone, with no read.
	var online := Online.new(h,h.identity,h.store)
	online.capabilities = {"mutations_enabled":true}
	var count: int = h.calls.size()
	_check(await online.prepare_archived_navigation() and h.calls.size() == count and online.coordinator != null and not online.coordinator.pending().is_empty(),"The held turn is restored from its saved proof")
	# The friend's phone removes the room; the list drops it and its proof.
	h.rooms.erase(ORDINARY)
	h.replies["/v2/capabilities"] = {"ok":true,"data":{"api_version":2,"simulation_version":2,"recording_version":2,"mutations_enabled":true,"validation":"structural_client_replay_required","chapters":[]}}
	h.replies["/v2/rooms"] = {"ok":true,"data":{"rooms":[h.rooms[NEXT_ROOM]]}}
	_check(await online.load_lobby() and not online.standalone_room_proven(ORDINARY) and online.room_ids() == [NEXT_ROOM],"The refreshed list no longer has the room")
	var old: RefCounted = online.coordinator
	_check(not await online.open_room(NEXT_ROOM) and online.last_room() == ORDINARY,"The bound turn still holds other rooms")
	var journals := _journals(h.store)
	var room_bytes := _room_bytes(h.store,ORDINARY)
	count = h.calls.size()
	_check(await online.prepare_archived_navigation() and online.coordinator == null and online.last_room().is_empty(),"The check releases the room and its coordinator")
	_check(h.calls.size() == count+1 and online.take_released_room_note() == PlayerCopy.ROOMS_API_A7ACF38988EE,"One GET, and one note")
	count = h.calls.size()
	_check(not await old.reconcile() and not await old.refresh() and old.pending().is_empty(),"The released coordinator's late retry sends nothing")
	_check(h.calls.size() == count and _journals(h.store) == journals,"Its late answers write nothing")
	_check(await online.open_room(NEXT_ROOM),"Other rooms open")
	_check(_room_bytes(h.store,ORDINARY) == room_bytes and not h.store.saved[_room_scope(ORDINARY)].pending.is_empty(),"The released turn's journal is unchanged")
	h.free()

## The app going to the background after the check finishes keeps the note for
## the next visit; a new identity drops it.
func _note_survives_backgrounding() -> void:
	var c := await _unproven_last_room(ORDINARY,"high-and-low")
	c.h.replies["/v2/rooms/"+ORDINARY] = GONE.deleted
	var online := _cold(c)
	_check(await online.prepare_archived_navigation(),"The room is released")
	var count: int = c.h.calls.size()
	_check(await online.prepare_archived_navigation() and c.h.calls.size() == count,"The next visit needs no second check")
	_check(online.take_released_room_note() == PlayerCopy.ROOMS_API_A7ACF38988EE,"The note waits until it is shown")
	_check(await online.prepare_archived_navigation() and online.take_released_room_note().is_empty(),"It is shown once")
	c.h.free()
	c = await _unproven_last_room(ORDINARY,"high-and-low")
	c.h.replies["/v2/rooms/"+ORDINARY] = GONE.deleted
	online = _cold(c)
	_check(await online.prepare_archived_navigation(),"The room is released")
	c.h.identity_value.epoch += 1
	_check(online.last_room().is_empty() and online.take_released_room_note().is_empty(),"A new identity never sees the old identity's note")
	c.h.free()

## Two phones holding the same gone room: one phone's release sends nothing
## that could change the other, which releases it on its own check.
func _two_phones() -> void:
	var c := await _unproven_last_room(ORDINARY,"high-and-low")
	c.h.replies["/v2/rooms/"+ORDINARY] = GONE.missing
	var other_store := MemoryStore.new()
	other_store.saved = c.h.store.saved.duplicate(true)
	var other_before: Dictionary = other_store.saved.duplicate(true)
	var room_bytes := _room_bytes(other_store,ORDINARY)
	var first := _cold(c)
	var second := Online.new(c.h,c.h.identity,other_store)
	second.capabilities = {"mutations_enabled":true}
	var count: int = c.h.calls.size()
	_check(await first.prepare_archived_navigation() and first.last_room().is_empty(),"The first phone releases the room")
	_check(c.h.calls.size() == count+1 and c.h.calls.back().method == HTTPClient.METHOD_GET,"It sends only its one read")
	_check(Canonical.same(other_before,other_store.saved) and second.last_room() == ORDINARY and not await second.open_room(NEXT_ROOM),"The second phone still holds its own turn until it checks")
	_check(await second.prepare_archived_navigation() and await second.open_room(NEXT_ROOM),"Its own check releases it too")
	_check(_room_bytes(other_store,ORDINARY) == room_bytes and _room_bytes(c.h.store,ORDINARY) == room_bytes,"Both phones keep the turn's journal unchanged")
	c.h.free()

## After the Story drain an old Story room drops out of the room lists (and the
## hub's inbox, which holds nothing) while every room route still answers 409
## campaign_client_required. A last Story room holding a lost-reply turn is
## released by that answer, before and after a list refresh that omits it.
func _story_room_left_lists() -> void:
	var c := await _unproven_last_room(STORY_ROOM,"high-and-low")
	c.h.rooms.erase(STORY_ROOM)
	c.h.replies["/v2/rooms/"+STORY_ROOM] = {"ok":false,"status":409,"code":"campaign_client_required"}
	c.h.replies["/v2/capabilities"] = {"ok":true,"data":{"api_version":2,"simulation_version":2,"recording_version":2,"mutations_enabled":true,"validation":"structural_client_replay_required","chapters":[]}}
	c.h.replies["/v2/rooms"] = {"ok":true,"data":{"rooms":[c.h.rooms[NEXT_ROOM]]}}
	var room_bytes := _room_bytes(c.h.store,STORY_ROOM)
	var online := _cold(c)
	_check(await online.load_lobby() and not STORY_ROOM in online.room_ids() and online.last_room() == STORY_ROOM,"Story: the list no longer shows the room, which is still the last room")
	_check(not await online.open_room(NEXT_ROOM),"Story: its held turn holds other rooms until it is checked")
	var count: int = c.h.calls.size()
	_check(await online.prepare_archived_navigation() and online.archived_room_kind(STORY_ROOM) == "story" and online.coordinator == null,"Story: the 409 answer releases navigation")
	_check(c.h.calls.size() == count+1 and c.h.calls.back().method == HTTPClient.METHOD_GET,"Story: one GET, and the turn is never sent")
	_check(online.take_released_room_note().is_empty(),"Story: a room that is not gone gets no closed note")
	_check(await online.open_room(NEXT_ROOM) and online.last_room() == NEXT_ROOM,"Story: other rooms open")
	_check(await online.load_lobby() and await online.prepare_archived_navigation() and await online.open_room(NEXT_ROOM),"Story: a later list refresh keeps other rooms open")
	_check(_room_bytes(c.h.store,STORY_ROOM) == room_bytes and not c.h.store.saved[_room_scope(STORY_ROOM)].pending.is_empty(),"Story: the room's journal keeps its exact bytes")
	c.h.free()

## A room this session read and found ordinary counts as proven only while the
## list shows it. Each tap below runs Main's order: check, then open.
## Alive but unlisted, with nothing held: one read keeps it, and another room
## opens on the first tap. Deleted with a held turn: that read releases it.
func _read_proof_follows_list(gone: bool) -> void:
	var label := "deleted: " if gone else "alive: "
	var h := ArchiveHarness.new()
	root.add_child(h)
	h.rooms[ORDINARY] = _room("high-and-low",ORDINARY,false)
	h.rooms[NEXT_ROOM] = _room("rolling-home",NEXT_ROOM,false)
	var online := Online.new(h,h.identity,h.store)
	_check(await online.open_room(NEXT_ROOM) and await online.open_room(ORDINARY) and online.archived_room_kind(ORDINARY) == "ordinary",label+"this session read the room and found it ordinary")
	online.capabilities = {"mutations_enabled":true}
	if gone:
		_check(not await online.coordinator.commit(_json("res://tests/fixtures/cooperative/upper-path-a.json")) and not online.coordinator.pending().is_empty(),label+"the turn's reply is lost")
		h.rooms.erase(ORDINARY)
	h.replies["/v2/capabilities"] = {"ok":true,"data":{"api_version":2,"simulation_version":2,"recording_version":2,"mutations_enabled":true,"validation":"structural_client_replay_required","chapters":[]}}
	h.replies["/v2/rooms"] = {"ok":true,"data":{"rooms":[h.rooms[NEXT_ROOM]]}}
	var room_bytes := _room_bytes(h.store,ORDINARY)
	_check(await online.load_lobby() and not online.standalone_room_proven(ORDINARY) and online.archived_room_kind(ORDINARY).is_empty(),label+"the list no longer shows the room, so its read proof is dropped")
	var count: int = h.calls.size()
	_check(await online.prepare_archived_navigation() and h.calls.size() == count+1 and h.calls.back().path == "/v2/rooms/"+ORDINARY,label+"the next tap reads the room once")
	if gone: _check(online.last_room().is_empty() and online.coordinator == null and online.take_released_room_note() == PlayerCopy.ROOMS_API_A7ACF38988EE,label+"the read finds it gone and releases it")
	else: _check(online.last_room() == ORDINARY and online.archived_room_kind(ORDINARY) == "ordinary" and online.take_released_room_note().is_empty(),label+"the read finds it alive and keeps it selected")
	_check(await online.open_room(NEXT_ROOM) and online.last_room() == NEXT_ROOM,label+"the same tap opens another room")
	_check(_room_bytes(h.store,ORDINARY) == room_bytes,label+"the room's journal keeps its exact bytes")
	h.free()
