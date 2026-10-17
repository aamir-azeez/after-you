extends SceneTree
const Session = preload("res://services/relay_online_session.gd")
const Client = preload("res://services/redo_client.gd")
const Recent = preload("res://tests/test_recent_rooms.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const HOST := Recent.HOST
const ROOM := Recent.ROOM
const OTHER := Recent.OTHER

class Api:
	extends Node
	var player_id := HOST
	var device_token := "synthetic-session-redo"
	var base_url := "https://synthetic.invalid"
	var busy := false
	var enabled := true
	var drop_accept := false
	var rooms: Dictionary = {}
	var receipt: Dictionary = {}
	var requested: Dictionary = {}
	var replies: Dictionary = {}
	var calls: Array = []
	func request_json(method: int, path: String, body: Dictionary = {}, _still: Callable = Callable()) -> Dictionary:
		calls.append({"path":path,"method":method,"body":body.duplicate(true)})
		if replies.has(path): return replies[path].duplicate(true)
		if path=="/v2/capabilities":
			var chapter := Registry.descriptor(Registry.RELAY)
			return _ok({"api_version":2,"recording_version":2,"simulation_version":2,"mutations_enabled":enabled,"validation":"structural_client_replay_required","chapters":[{"level_id":chapter.level_id,"level_version":chapter.level_version,"definition_hash":chapter.definition_hash,"premium":false}]})
		if path=="/v2/rooms": return _ok({"rooms":rooms.values()})
		if path.get_file() in rooms: return _ok(rooms[path.get_file()])
		if "/operations/" in path:
			return _ok(receipt) if receipt.get("receipt",{}).get("idempotency_key")==path.get_file() else {"ok":false,"status":404,"code":"operation_not_found"}
		if path.ends_with("/redo"):
			var source := Client.source_for("relay",rooms[ROOM])
			return _ok({"schema_version":1,"source":null if source.is_empty() else source,"request":null if source.is_empty() else requested})
		if path.ends_with("/fork"):
			if not enabled: return {"ok":false,"status":503,"code":"v2_mutations_disabled"}
			var room: Dictionary = rooms[ROOM]
			room.revision+=1
			room.branch+=1
			room.active_role="a"
			room.active_player_id=HOST
			room.a_turn_id=null
			room.recording_a=null
			var hash_body := body.duplicate(true)
			hash_body.operation="fork"
			receipt={"room":room.duplicate(true),"receipt":{"schema_version":2,"room_id":ROOM,"idempotency_key":body.idempotency_key,"request_hash":Canonical.digest(hash_body),"operation":"fork","accepted_revision":room.revision,"branch":room.branch,"stage_index":room.stage_index,"stage_id":room.stage_id,"checkpoint_hash":room.checkpoint.checkpoint_hash,"turn_id":null,"recording_hash":null,"pair_id":null}}
			if drop_accept:
				drop_accept=false
				return {"ok":false,"status":0,"code":"connection_interrupted"}
			return _ok(receipt)
		return {"ok":false,"status":404,"code":"room_not_found" if path.get_file().length()==22 else "not_found"}
	func _ok(value: Dictionary) -> Dictionary: return {"ok":true,"data":value.duplicate(true)}

var checks := 0
var failures := 0
func _initialize() -> void: _run.call_deferred()
func _check(value: bool, label: String) -> bool:
	checks+=1
	if not value:
		failures+=1
		push_error(label)
	return value
func _room(id: String, has_a: bool) -> Dictionary:
	var level := Registry.definition(Registry.RELAY)
	var chapter := Registry.descriptor(Registry.RELAY)
	return {"api_version":2,"schema_version":2,"room_id":id,"revision":2 if has_a else 1,"branch":0,"stage_index":0,"level_id":chapter.level_id,"level_version":chapter.level_version,"definition_hash":chapter.definition_hash,"host_id":HOST,"guest_id":Recent.GUEST,
		"checkpoint":JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/v2/initial-checkpoint.json")),"a_turn_id":"t0-0-a" if has_a else null,"completed_pair_ids":[],"invite_expires_at":"2026-09-28T00:00:00Z","created_at":"2026-09-21T00:00:00Z","updated_at":"2026-09-27T00:00:00Z",
		"active_role":"b" if has_a else "a","first_player_id":HOST,"active_player_id":Recent.GUEST if has_a else HOST,"player_slot":"p0","invite_code":"A1".repeat(10),"stage_id":level.stages[0].id,"recording_a":JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/v2/relay-a.json")) if has_a else null,"validation":"structural_client_replay_required"}
func _run() -> void:
	var api := Api.new()
	root.add_child(api)
	api.rooms={ROOM:_room(ROOM,true),OTHER:_room(OTHER,false)}
	var source := Client.source_for("relay",api.rooms[ROOM])
	api.requested={"request_id":Canonical.digest(source),"source":source,"status":"pending"}
	var identity := Recent.Identity.new()
	identity.player=HOST
	var store := Recent.MemoryStore.new()
	var session := Session.new(api,identity.current,store)
	if not _check(await session.load_lobby() and await session.open_room(ROOM),"Actual Session opens a replay-verified accepted A turn"):
		push_error(session.last_error)
		api.queue_free()
		quit(1)
		return
	var client: RefCounted = session.redo_client()
	_check(client.bind_room("relay",session.coordinator.snapshot()) and await client.refresh() and client.can_accept(),"Session's shared client reads first-player consent")
	_check(client.bind_room("relay",session.coordinator.snapshot()) and client.can_accept(),"Rendering an unchanged bound room preserves its verified request indicator")
	api.drop_accept=true
	_check(not await client.accept() and not client.pending().is_empty(),"Accepted fork with lost reply retains the Session's redo journal")
	var redo_scope := "relay-redo-relay-v1:"+HOST+":"+ROOM
	if not store.values.has(redo_scope):
		push_error(client.last_error)
		api.queue_free()
		quit(1)
		return
	var held: Dictionary = store.values[redo_scope].duplicate(true)
	var calls := api.calls.size()
	_check(not await session.open_room(OTHER) and session.last_room()==ROOM and api.calls.size()==calls,"Warm room switching cannot hide pending acceptance or change last_room")
	_check(not session.can_leave_for_legacy() and (await session.create_room()).is_empty() and (await session.join_room("A1".repeat(10))).is_empty() and api.calls.size()==calls,"Legacy, create, and join respect the same unresolved redo hold")
	session=Session.new(api,identity.current,store)
	_check(await session.load_lobby(),"Cold Session can still list rooms while a redo receipt needs recovery")
	calls=api.calls.size()
	_check(not await session.open_room(OTHER) and session.last_room()==ROOM and api.calls.size()==calls,"Cold switch restores the previous room's control hold before any target GET")
	_check(not session.can_leave_for_legacy() and (await session.create_room()).is_empty(),"Cold legacy and creation cannot bypass the control journal")
	var reads: int = store.reads
	for iteration in range(60): session.can_leave_for_legacy()
	_check(store.reads==reads,"Repeated notification guards do not reread the control journal every frame")
	_check(await session.open_room(ROOM) and session.coordinator.snapshot().active_role=="a","Same-room recovery refreshes the accepted fork through normal native validation")
	client=session.redo_client()
	_check(client.bind_room("relay",session.coordinator.snapshot()) and client.pending().action=="accept","Cold accepted A snapshot still restores the old-source pending control")
	api.enabled=false
	_check(await session.load_lobby() and not session.mutations_enabled(),"Recovery fixture pauses further chapter mutations")
	calls=api.calls.size()
	_check(await client.retry(false) and client.accepted and client.pending().is_empty(),"Paused service reconciles accepted fork through its existing GET receipt")
	_check(api.calls.size()==calls+1 and api.calls.back().method==HTTPClient.METHOD_GET and "/operations/" in api.calls.back().path,"Receipt recovery performs no POST while mutations are disabled")
	_check(session.can_leave_for_legacy() and await session.open_room(OTHER),"Resolving the same durable request releases normal navigation")
	store.values[redo_scope]=held
	store.values["relay-lobby-v2:"+HOST].last_room=ROOM
	api.rooms.erase(ROOM)
	var room_scope := "relay-room-v2:"+HOST+":"+ROOM
	var journals := _journals(store,[redo_scope,room_scope])
	session=Session.new(api,identity.current,store)
	# The omitted room lost its standalone proof with its list row, so it is
	# checked once before anything else. A check that times out keeps it held.
	api.replies["/v2/rooms/"+ROOM]={"ok":false,"status":0,"code":"request_timeout"}
	_check(await session.load_lobby() and session.room_ids()==[OTHER] and session.pending_redo_room()==ROOM,"Cold omitted room whose check times out retains an explicit validated recovery target")
	_check(not await session.open_room(OTHER) and session.pending_redo_room()==ROOM,"List omission and a timeout never discard uncertain acceptance")
	calls=api.calls.size()
	_check(not await session.open_room(ROOM) and session.pending_redo_room()==ROOM and api.calls.size()==calls,"An unproven omitted room is never opened unchecked")
	_check(not await session.prepare_archived_navigation() and session.pending_redo_room()==ROOM and not await session.open_room(OTHER),"A check that times out keeps the uncertain redo and holds other rooms")
	_check(session.take_released_room_note().is_empty() and journals==_journals(store,[redo_scope,room_scope]),"A timeout releases and writes nothing")
	api.replies.clear()
	calls=api.calls.size()
	_check(await session.prepare_archived_navigation() and session.pending_redo_room().is_empty() and session.last_room().is_empty(),"A check that finds the room gone releases its uncertain redo")
	_check(api.calls.size()==calls+1 and api.calls.back().method==HTTPClient.METHOD_GET,"The check is one GET and no mutation")
	_check(session.take_released_room_note()==PlayerCopy.ROOMS_API_A7ACF38988EE and session.take_released_room_note().is_empty(),"The player is told once that the room was closed")
	_check(await session.open_room(OTHER) and session.last_room()==OTHER,"Other rooms open again")
	_check(journals==_journals(store,[redo_scope,room_scope]),"The redo and room journals keep their exact bytes")
	# A cold start that still holds the room's proof. One tap runs Main's order
	# (relay_lobby_flow.lobby_action): check, list refresh, check again, open.
	var index: Dictionary = store.values["relay-lobby-v2:"+HOST]
	index.last_room=ROOM
	index.room_ids=[ROOM,OTHER]
	index.standalone_ids=[ROOM,OTHER]
	session=Session.new(api,identity.current,store)
	calls=api.calls.size()
	_check(await session.prepare_archived_navigation() and session.pending_redo_room()==ROOM and api.calls.size()==calls,"The proven room is restored with no read")
	_check(await session.load_lobby() and not session.standalone_room_proven(ROOM) and session.pending_redo_room()==ROOM,"The list refresh drops its proof and releases nothing by itself")
	_check(await session.prepare_archived_navigation() and session.pending_redo_room().is_empty() and session.last_room().is_empty(),"The check after the refresh finds the room gone and releases its redo")
	_check(api.calls.size()==calls+3 and api.calls.back().path=="/v2/rooms/"+ROOM and api.calls.back().method==HTTPClient.METHOD_GET,"Capabilities, the list and one room GET; no mutation")
	_check(await session.open_room(OTHER) and session.last_room()==OTHER,"The same tap opens another room")
	_check(journals==_journals(store,[redo_scope,room_scope]),"The released journals still keep their exact bytes")
	api.queue_free()
	await process_frame
	await _warm_gone_redo()
	print("After You redo Session integration: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _journals(store: RefCounted, scopes: Array) -> PackedByteArray:
	return var_to_bytes(scopes.map(func(scope: String) -> Variant: return store.values.get(scope)))

## A Session restored from the room's saved proof, with its redo client bound
## to the lost-reply redo. The friend's phone then removes the room; after the
## list drops it, the next tap's one check releases the redo, and the released
## client's late retry sends nothing.
func _warm_gone_redo() -> void:
	var api := Api.new()
	root.add_child(api)
	api.rooms={ROOM:_room(ROOM,true),OTHER:_room(OTHER,false)}
	var source := Client.source_for("relay",api.rooms[ROOM])
	api.requested={"request_id":Canonical.digest(source),"source":source,"status":"pending"}
	var identity := Recent.Identity.new()
	identity.player=HOST
	var store := Recent.MemoryStore.new()
	var first := Session.new(api,identity.current,store)
	_check(await first.load_lobby() and await first.open_room(OTHER) and await first.open_room(ROOM),"Warm: both rooms open")
	var first_client: RefCounted = first.redo_client()
	_check(first_client.bind_room("relay",first.coordinator.snapshot()) and await first_client.refresh(),"Warm: the redo request is read")
	api.drop_accept=true
	_check(not await first_client.accept() and not first_client.pending().is_empty(),"Warm: the accept's reply is lost")
	var session := Session.new(api,identity.current,store)
	var calls := api.calls.size()
	_check(await session.load_lobby() and await session.prepare_archived_navigation() and api.calls.size()==calls+2 and session.coordinator!=null,"Warm: a later start restores the room from its saved proof, with no room read")
	var client: RefCounted = session.redo_client()
	_check(client.bind_room("relay",session.coordinator.snapshot()) and client.pending().action=="accept","Warm: its redo client loads the lost-reply accept")
	var journals := _journals(store,["relay-redo-relay-v1:"+HOST+":"+ROOM,"relay-room-v2:"+HOST+":"+ROOM])
	calls = api.calls.size()
	_check(not await session.open_room(OTHER) and api.calls.size()==calls,"Warm: the uncertain redo holds other rooms")
	api.rooms.erase(ROOM)
	_check(await session.load_lobby() and session.room_ids()==[OTHER] and not session.standalone_room_proven(ROOM),"Warm: the list no longer shows the room, so it is checked before its next use")
	_check(await session.prepare_archived_navigation() and client.pending().is_empty() and session.pending_redo_room().is_empty() and session.coordinator==null,"Warm: the next tap's check releases the redo and the room")
	_check(api.calls.size()==calls+3 and api.calls.back().path=="/v2/rooms/"+ROOM and api.calls.back().method==HTTPClient.METHOD_GET,"Warm: one room GET and no mutation")
	calls=api.calls.size()
	_check(not await client.retry() and not await client.refresh() and api.calls.size()==calls,"Warm: the released client's late retry sends nothing")
	_check(await session.open_room(OTHER) and session.last_room()==OTHER,"Warm: the same tap opens another room")
	_check(journals==_journals(store,["relay-redo-relay-v1:"+HOST+":"+ROOM,"relay-room-v2:"+HOST+":"+ROOM]),"Warm: the redo and room journals keep their exact bytes")
	api.queue_free()
	await process_frame
