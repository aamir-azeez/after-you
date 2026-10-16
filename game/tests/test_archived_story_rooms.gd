extends SceneTree
## Rooms from the withdrawn Story feature stay out of ordinary play. The server
## answers an ordinary read of one with 409 campaign_client_required; that answer
## is the only evidence used, and it lives in memory for one identity. A room
## this phone has not proven ordinary is read and checked before it is used.
const Online = preload("res://services/relay_online_session.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const HOST := "HHHHHHHHHHHHHHHHHHHHHH"
const GUEST := "GGGGGGGGGGGGGGGGGGGGGG"
const ORDINARY := "OOOOOOOOOOOOOOOOOOOOOO"
const NEXT_ROOM := "NNNNNNNNNNNNNNNNNNNNNN"
const STORY_ROOM := "SSSSSSSSSSSSSSSSSSSSSS"
var checks := 0
var failures := 0

class MemoryStore:
	extends RefCounted
	var saved: Dictionary = {}
	var fail_scope := ""
	var on_save: Callable
	func load_scope(scope: String) -> Dictionary:
		return {"ok":true,"found":saved.has(scope),"value":saved.get(scope,{}).duplicate(true)}
	func save_scope(scope: String, value: Dictionary) -> Dictionary:
		if scope == fail_scope: return {"ok":false}
		saved[scope] = JSON.parse_string(JSON.stringify(value))
		if on_save.is_valid(): on_save.call(scope)
		return {"ok":true}

class ArchiveHarness:
	extends Node
	var player_id := HOST
	var device_token := "synthetic-device-token"
	var base_url := "https://synthetic.invalid"
	var busy := false
	var identity_value := {"ready":true,"player_id":HOST,"epoch":1}
	var store := MemoryStore.new()
	var rooms: Dictionary = {}
	var replies: Dictionary = {}
	var calls: Array = []
	var on_request: Callable
	func identity() -> Dictionary: return identity_value.duplicate(true)
	func request_json(method: int, path: String, body: Dictionary = {}, _still: Callable = Callable()) -> Dictionary:
		busy = true
		calls.append({"method":method,"path":path,"body":body.duplicate(true)})
		if on_request.is_valid(): on_request.call()
		await get_tree().process_frame
		busy = false
		if replies.has(path): return replies[path].duplicate(true)
		if method != HTTPClient.METHOD_GET: return {"ok":false,"status":0,"code":"connection_interrupted"}
		var room := path.get_slice("/",3)
		return {"ok":true,"status":200,"data":rooms[room].duplicate(true)} if rooms.has(room) else {"ok":false,"status":404,"code":"room_not_found"}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await _story_last_room()
	await _story_probe()
	await _schema_one_ordinary_pending()
	await _unknown_replies_hold()
	await _classification_lifetime()
	print("Archived Story rooms: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)

## A harness whose last room was opened by an older build: its index has no
## standalone proof, so this build cannot tell yet what kind of room it is.
func _unproven_last_room(room_id: String, chapter: String) -> Dictionary:
	var h := ArchiveHarness.new()
	root.add_child(h)
	h.rooms[room_id] = _room(chapter,room_id,false)
	h.rooms[NEXT_ROOM] = _room("rolling-home",NEXT_ROOM,false)
	var online := Online.new(h,h.identity,h.store)
	_check(await online.open_room(room_id),"The room was opened earlier")
	online.capabilities = {"mutations_enabled":true}
	_check(not await online.coordinator.commit(_json("res://tests/fixtures/cooperative/upper-path-a.json")) and not online.coordinator.pending().is_empty(),"The room keeps an uncertain turn")
	var index: Dictionary = h.store.saved["relay-lobby-v2:"+HOST]
	index.erase("standalone_ids")
	index.schema_version = 1
	return {"h":h}

func _cold(c: Dictionary) -> RefCounted:
	var online := Online.new(c.h,c.h.identity,c.h.store)
	online.capabilities = {"mutations_enabled":true}
	return online

func _story_last_room() -> void:
	var c := await _unproven_last_room(STORY_ROOM,"high-and-low")
	c.h.store.saved["relay-campaign-lobby-v1:"+HOST] = {"retained":"unchanged"}
	var before: Dictionary = c.h.store.saved.duplicate(true)
	var online := _cold(c)
	var count: int = c.h.calls.size()
	_check(not online.can_leave_for_legacy() and not await online.open_room(ORDINARY) and c.h.calls.size() == count,"An unproven last room holds navigation before any request")
	c.h.replies["/v2/rooms/"+STORY_ROOM] = {"ok":false,"status":409,"code":"campaign_client_required"}
	_check(await online.prepare_archived_navigation() and online.can_leave_for_legacy(),"The server's Story answer releases navigation")
	_check(c.h.calls.size() == count+1 and c.h.calls.back().method == HTTPClient.METHOD_GET and c.h.calls.back().path == "/v2/rooms/"+STORY_ROOM,"The old room is read once and its saved turn is never sent")
	_check(online.archived_room_kind(STORY_ROOM) == "story" and online.coordinator == null and online.pending_redo_room().is_empty(),"The Story room is never bound as an ordinary recovery room")
	_check(Canonical.same(before,c.h.store.saved),"Its journal, pending turn and old Story files stay exactly as they were")
	_check(not await online.open_room(STORY_ROOM) and online.last_error == preload("res://presentation/player_copy.gd").RELAY_ONLINE_SESSION_28632F597E2A,"Ordinary entry refuses the Story room")
	_check(not online._transfer_eligibility(STORY_ROOM).get("ok",false) and not online._history_eligibility(STORY_ROOM).get("ok",false),"Its replays are never moved to this phone")
	var factory: RefCounted = online.auxiliary_context_factory()
	for purpose: String in ["presence","photo","replay","safety"]:
		_check(not factory.for_room(STORY_ROOM,purpose).current(),"The Story room has no "+purpose+" requests")
	c.h.rooms[ORDINARY] = _room("high-and-low",ORDINARY,false)
	_check(await online.open_room(ORDINARY),"An ordinary chapter opens beside it")
	_check(c.h.store.saved["relay-lobby-v2:"+HOST].standalone_ids == [ORDINARY],"Only the checked room gets a standalone proof")
	for purpose: String in ["presence","photo","replay","safety"]:
		_check(factory.for_room(ORDINARY,purpose).current(),"The ordinary room keeps its "+purpose+" requests")
	_check(Canonical.same(before["relay-campaign-lobby-v1:"+HOST],c.h.store.saved["relay-campaign-lobby-v1:"+HOST]),"The old Story file is untouched")
	online.invalidate_identity()
	_check(online.archived_room_kind(STORY_ROOM).is_empty(),"The evidence ends with the identity")
	c.h.free()

## A room this phone never proved ordinary, answered as a Story room on its
## first check, is kept out of photo, replay, history and redo handling too.
func _story_probe() -> void:
	var h := ArchiveHarness.new()
	root.add_child(h)
	var online := Online.new(h,h.identity,h.store)
	online.capabilities = {"mutations_enabled":true}
	h.replies["/v2/rooms/"+STORY_ROOM] = {"ok":false,"status":409,"code":"campaign_client_required"}
	var count: int = h.calls.size()
	_check(not await online.open_room(STORY_ROOM) and online.last_error == preload("res://presentation/player_copy.gd").RELAY_ONLINE_SESSION_28632F597E2A,"The first check of a Story room refuses it")
	_check(h.calls.size() == count+1 and online.archived_room_kind(STORY_ROOM) == "story","One read records the server's Story answer")
	_check(online.last_room().is_empty() and not h.store.saved.has(_room_scope(STORY_ROOM)),"Nothing about the Story room is selected or cached")
	var factory: RefCounted = online.auxiliary_context_factory()
	for purpose: String in ["photo","replay","presence","safety"]:
		_check(not factory.for_room(STORY_ROOM,purpose).current(),"The Story room has no "+purpose+" requests after the check")
	_check(not online._history_eligibility(STORY_ROOM).get("ok",false) and not online._transfer_eligibility(STORY_ROOM).get("ok",false),"Its history and replay transfer stay closed")
	count = h.calls.size()
	_check(not await online.open_room(STORY_ROOM) and h.calls.size() == count,"A second open is refused without asking again")
	h.free()

func _schema_one_ordinary_pending() -> void:
	var c := await _unproven_last_room(ORDINARY,"high-and-low")
	var before: Dictionary = c.h.store.saved.duplicate(true)
	var online := _cold(c)
	var count: int = c.h.calls.size()
	_check(not online.can_leave_for_legacy() and not await online.open_room(NEXT_ROOM),"A missing standalone proof cannot release the old pending turn")
	_check(online.coordinator == null and c.h.calls.size() == count,"The unknown room is held before its cache loads or another room is read")
	_check(await online.prepare_archived_navigation(),"A checked ordinary read identifies the old room")
	_check(c.h.calls.size() == count+1 and c.h.calls.back().method == HTTPClient.METHOD_GET and c.h.calls.back().path == "/v2/rooms/"+ORDINARY,"One GET and no turn POST")
	var pending: Dictionary = online.coordinator.pending() if online.coordinator != null else {}
	_check(online.coordinator != null and not pending.is_empty(),"The exact pending journal is restored")
	_check(Canonical.same(before,c.h.store.saved),"Identifying it writes nothing")
	count = c.h.calls.size()
	_check(not online.can_leave_for_legacy() and not await online.open_room(NEXT_ROOM),"The restored pending turn still blocks another room")
	_check(c.h.calls.size() == count and Canonical.same(before,c.h.store.saved),"Leaving cannot resend or erase it")
	_check(await online.open_room(ORDINARY) and Canonical.same(pending,online.coordinator.pending()),"Opening the same room keeps its recovery request")
	online.invalidate_identity()
	_check(online.archived_room_kind(ORDINARY).is_empty(),"Invalidating the identity drops what was learned")
	c.h.free()

func _unknown_replies_hold() -> void:
	for failure: String in ["offline","timeout","forbidden","missing","server","other409","wrong_room","wrong_proof"]:
		var c := await _unproven_last_room(ORDINARY,"high-and-low")
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
		var online := _cold(c)
		var count: int = c.h.calls.size()
		_check(not await online.prepare_archived_navigation(),failure+" proves neither a Story nor an ordinary room")
		_check(c.h.calls.size() == count+1 and c.h.calls.back().path == "/v2/rooms/"+ORDINARY,failure+": only the previous room is read")
		_check(online.coordinator == null and online.archived_room_kind(ORDINARY).is_empty() and Canonical.same(before,c.h.store.saved),failure+" keeps the cache, pending turn and selection")
		_check(not online.can_leave_for_legacy() and not await online.open_room(NEXT_ROOM) and c.h.calls.size() == count+1,failure+" cannot release the pending turn or read another room")
		c.h.free()

func _classification_lifetime() -> void:
	for change: String in ["epoch","device","backend","selection"]:
		var c := await _unproven_last_room(ORDINARY,"high-and-low")
		var online := _cold(c)
		var before: Dictionary = c.h.store.saved.duplicate(true)
		c.h.on_request = func():
			match change:
				"epoch": c.h.identity_value.epoch += 1
				"device": c.h.device_token = "synthetic-replacement-device"
				"backend": c.h.base_url = "https://replacement.synthetic.invalid"
				"selection": online._room_selection_generation += 1
		_check(not await online.prepare_archived_navigation(),"A changed "+change+" rejects the late answer")
		_check(online.archived_room_kind(ORDINARY).is_empty() and Canonical.same(before,c.h.store.saved),"A stale "+change+" answer records nothing and saves nothing")
		c.h.on_request = Callable()
		c.h.free()

func _room(chapter: String, room_id: String, complete: bool) -> Dictionary:
	var level := Registry.definition(chapter+"@1")
	return {"schema_version":2,"api_version":2,"simulation_version":6,"room_id":room_id,"revision":5 if complete else 1,"branch":0,
		"stage_index":2 if complete else 0,"level_id":level.id,"level_version":level.version,"definition_hash":Canonical.digest(level),
		"host_id":HOST,"guest_id":GUEST,"checkpoint":_json("res://tests/fixtures/cooperative/"+chapter+("-final-checkpoint" if complete else "-initial-checkpoint")+".json"),
		"a_turn_id":null,"completed_pair_ids":["p0-0","p0-1"] if complete else [],"invite_code":"AB".repeat(10),"invite_expires_at":"2026-10-04T13:00:00.000Z",
		"created_at":"2026-09-27T12:00:00Z","updated_at":"2026-09-27T12:00:00Z","active_role":"complete" if complete else "a","first_player_id":null if complete else HOST,
		"active_player_id":null if complete else HOST,"player_slot":"p0","stage_id":"" if complete else level.stages[0].id,"recording_a":null,"validation":"structural_client_replay_required"}

func _room_scope(room: String) -> String: return "relay-room-v2:"+HOST+":"+room
func _json(path: String) -> Dictionary: return JSON.parse_string(FileAccess.get_file_as_string(path))
func _check(condition: bool, message: String) -> bool:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
	return condition
