extends SceneTree
const Session = preload("res://services/relay_online_session.gd")
const Client = preload("res://services/redo_client.gd")
const Recent = preload("res://tests/test_recent_rooms.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Canonical = preload("res://core/v2/canonical.gd")
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
	var calls: Array = []
	func request_json(method: int, path: String, body: Dictionary = {}) -> Dictionary:
		calls.append({"path":path,"method":method,"body":body.duplicate(true)})
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
	session=Session.new(api,identity.current,store)
	_check(await session.load_lobby() and session.room_ids()==[OTHER] and session.pending_redo_room()==ROOM,"Cold omitted room retains an explicit validated recovery target")
	_check(not await session.open_room(OTHER) and session.pending_redo_room()==ROOM,"List omission alone never discards uncertain acceptance")
	calls=api.calls.size()
	_check(not await session.open_room(ROOM) and session.pending_redo_room().is_empty(),"Explicit missing-room GET clears only its matching valid control hold")
	_check(api.calls.size()==calls+1 and api.calls.back().method==HTTPClient.METHOD_GET and await session.open_room(OTHER),"Deleted-room recovery performs no mutation and restores access to other rooms")
	api.queue_free()
	await process_frame
	print("After You redo Session integration: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
