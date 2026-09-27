extends SceneTree
const Session = preload("res://services/relay_online_session.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const HOST := "HHHHHHHHHHHHHHHHHHHHHH"
const GUEST := "GGGGGGGGGGGGGGGGGGGGGG"
const ROOM := "RRRRRRRRRRRRRRRRRRRRRR"
const OTHER := "SSSSSSSSSSSSSSSSSSSSSS"

class MemoryStore:
	extends RefCounted
	var values: Dictionary = {}
	var reads := 0
	func load_scope(scope: String) -> Dictionary:
		reads += 1
		return {"ok":true,"found":values.has(scope),"value":values.get(scope,{}).duplicate(true)}
	func save_scope(scope: String, value: Dictionary) -> Dictionary:
		values[scope] = value.duplicate(true)
		return {"ok":true}

class Identity:
	extends RefCounted
	var player := GUEST
	var epoch := 1
	func current() -> Dictionary:
		return {"ready":true,"player_id":player,"epoch":epoch}

class Api:
	extends Node
	signal release
	var player_id := GUEST
	var device_token := "synthetic-token"
	var base_url := "https://synthetic.invalid"
	var busy := false
	var listed: Array = []
	var fail_list := false
	var hold_read := false
	var lookup: Dictionary = {}
	func request_json(_method: int, path: String, _body: Dictionary = {}) -> Dictionary:
		busy = true
		if hold_read:
			hold_read = false
			await release
		busy = false
		if path == "/v2/capabilities":
			var descriptor := Registry.descriptor(Registry.RELAY)
			return {"ok":true,"data":{"api_version":2,"recording_version":2,"simulation_version":2,"mutations_enabled":true,"validation":"structural_client_replay_required","chapters":[{"level_id":descriptor.level_id,"level_version":descriptor.level_version,"definition_hash":descriptor.definition_hash,"premium":false}]}}
		if path == "/v2/rooms":
			return {"ok":false,"status":503,"code":"unavailable"} if fail_list else {"ok":true,"data":{"rooms":listed.duplicate(true)}}
		var id := path.get_file()
		return {"ok":true,"data":lookup[id].duplicate(true)} if lookup.has(id) else {"ok":false,"status":404,"code":"room_not_found"}

var checks := 0
var failures := 0
func _initialize() -> void:
	_run.call_deferred()
func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
func _room(id: String, hosted: bool = false) -> Dictionary:
	var chapter := Registry.descriptor(Registry.RELAY)
	var level := Registry.definition(Registry.RELAY)
	var value := {"api_version":2,"schema_version":2,"room_id":id,"revision":1,"branch":0,"stage_index":0,
		"level_id":chapter.level_id,"level_version":chapter.level_version,"definition_hash":chapter.definition_hash,
		"host_id":GUEST if hosted else HOST,"guest_id":HOST if hosted else GUEST,
		"checkpoint":JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/v2/initial-checkpoint.json")),
		"a_turn_id":null,"completed_pair_ids":[],"invite_expires_at":"2026-09-28T00:00:00Z","created_at":"2026-09-21T00:00:00Z","updated_at":"2026-09-27T00:00:00Z",
		"active_role":"a","first_player_id":GUEST if hosted else HOST,"active_player_id":GUEST if hosted else HOST,
		"player_slot":"p0" if hosted else "p1","stage_id":level.stages[0].id,"recording_a":null,"validation":"structural_client_replay_required"}
	if hosted: value["invite_code"] = "A1".repeat(10)
	return value
func _run() -> void:
	var api := Api.new()
	root.add_child(api)
	var identity := Identity.new()
	var store := MemoryStore.new()
	var scope := "relay-lobby-v2:" + GUEST
	store.values[scope] = {"schema_version":1,"owner_player_id":GUEST,"room_ids":[ROOM],"last_room":ROOM,"pending":{}}
	var session := Session.new(api, identity.current, store)
	_check(session.room_ids().is_empty(), "Cold local hints are not presented as authenticated visible rooms")
	api.listed = [_room(OTHER, true), _room(ROOM)]
	api.lookup = {ROOM:_room(ROOM),OTHER:_room(OTHER)}
	_check(await session.load_lobby(), "A guest and hosted room both load through the same authenticated list")
	var summaries := session.room_summaries()
	_check(session.room_ids() == [ROOM, OTHER], "The most recently opened guest room appears first")
	_check(summaries.size() == 2 and not summaries[0].hosted and summaries[1].hosted, "Summary keeps guest memberships without host-only filtering")
	_check(summaries[0].title == "The Relay Isles" and summaries[0].last_opened, "Summary has the established title and last-opened marker")
	_check(await session.open_room(OTHER), "A recent room opens directly without its expired invitation")
	_check(session.room_ids() == [OTHER, ROOM], "Opening a room moves it to the front of the durable recent order")
	var saved_journal: Dictionary = store.values["relay-room-v2:" + GUEST + ":" + OTHER].duplicate(true)
	session = Session.new(api, identity.current, store)
	_check(await session.load_lobby() and session.room_ids() == [OTHER, ROOM], "Reconnection restores guest recent ordering")
	api.listed = [_room(ROOM)]
	_check(await session.load_lobby() and session.room_ids() == [ROOM], "Server-hidden or deleted rooms do not survive through local index hints")
	_check(session.last_room() == OTHER and Canonical.same(saved_journal, store.values["relay-room-v2:" + GUEST + ":" + OTHER]), "Removing a list hint preserves selected recovery target and its journal")
	api.fail_list = true
	_check(not await session.load_lobby() and session.room_summaries().is_empty(), "Failed refresh cannot show an old room as currently accessible")
	api.fail_list = false
	api.listed = [_room(ROOM)]
	_check(await session.load_lobby(), "Successful manual refresh restores currently accessible guest room")
	api.lookup.erase(ROOM)
	_check(not await session.open_room(ROOM) and session.room_ids().is_empty(), "A now-deleted room is removed after its direct authenticated read fails")
	api.lookup[ROOM] = _room(ROOM)
	_check(await session.open_room(ROOM), "Same room can recover without discarding its saved state")
	api.hold_read = true
	var completed := {"done":false,"value":true}
	_open_into(session, completed)
	_check(api.busy, "Identity replacement test holds an actual asynchronous room read")
	identity.player = HOST
	identity.epoch += 1
	api.player_id = HOST
	session.invalidate_identity()
	api.release.emit()
	await process_frame
	_check(completed.done and not completed.value and session.room_ids().is_empty(), "An old-identity room read cannot repopulate recent rooms")
	api.queue_free()
	await process_frame
	print("After You recent rooms: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
func _open_into(session: RefCounted, result: Dictionary) -> void:
	result.value = await session.open_room(ROOM)
	result.done = true
