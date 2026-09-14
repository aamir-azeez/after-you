extends SceneTree

const Main = preload("res://main.gd")
const Session = preload("res://services/relay_online_session.gd")
const DiskStore = preload("res://services/relay_online_store.gd")
const Save = preload("res://services/local_save.gd")
const Catalog = preload("res://core/v2/stage_catalog.gd")
const Simulation = preload("res://core/v2/simulation_v2.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const HOST := "HHHHHHHHHHHHHHHHHHHHHH"
const GUEST := "GGGGGGGGGGGGGGGGGGGGGG"
const ROOM := "40173cc9d5bee436613f7a"

class MemoryStore:
	extends RefCounted
	var values: Dictionary = {}
	var writes := 0
	var fail := false
	var fail_read_scope := ""
	func load_scope(scope: String) -> Dictionary:
		if scope == fail_read_scope:
			return {"ok":false}
		return {"ok":true,"found":values.has(scope),"value":values.get(scope,{}).duplicate(true)}
	func save_scope(scope: String, value: Dictionary) -> Dictionary:
		if fail:
			return {"ok":false}
		writes += 1
		values[scope] = JSON.parse_string(JSON.stringify(value))
		return {"ok":true}

class Identity:
	extends RefCounted
	var player := HOST
	var epoch := 1
	var ready := true
	func get_value() -> Dictionary:
		return {"ready":ready,"player_id":player,"epoch":epoch}

class FakeApi:
	extends Node
	signal release
	var player_id := HOST
	var device_token := "synthetic-device-token"
	var base_url := "https://synthetic.invalid"
	var busy := false
	var enabled := true
	var exists := false
	var joined := false
	var index := 0
	var has_a := false
	var revision := 0
	var creation_keys: Dictionary = {}
	var receipts: Dictionary = {}
	var calls: Array = []
	var drop_next := false
	var hold_next := false
	var responder: Callable
	var wrong_join := false
	func configured() -> bool:
		return true
	func request_json(method: int, path: String, body: Dictionary = {}) -> Dictionary:
		busy = true
		var captured := {"method":method,"path":path,"body":body.duplicate(true),"owner":player_id}
		calls.append(captured)
		if hold_next:
			hold_next = false
			await release
		var response: Dictionary = responder.call(captured)
		busy = false
		if drop_next and method==HTTPClient.METHOD_POST:
			drop_next = false
			return {"ok":false,"status":0,"code":"connection_interrupted","error":"Synthetic interrupted response."}
		return JSON.parse_string(JSON.stringify(response))

var fixtures: Dictionary = {}
var level := Catalog.relay_isles()
var checks := 0
var failures := 0
var cleanup_paths: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for name: String in ["relay-a","relay-b","garden-a","garden-b","initial-checkpoint","relay-checkpoint","final-checkpoint"]:
		fixtures[name] = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/v2/"+name+".json"))
	await _adapter_lobby()
	await _adapter_holds()
	await _real_ui_flow()
	_disk_boundaries()
	for path: String in cleanup_paths:
		for suffix: String in ["", ".tmp", ".backup"]:
			if FileAccess.file_exists(path+suffix):
				DirAccess.remove_absolute(path+suffix)
	print("After You online Relay integration: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _api() -> FakeApi:
	var api := FakeApi.new()
	api.responder = _server.bind(api)
	root.add_child(api)
	return api

func _snapshot(api: FakeApi, owner: String) -> Dictionary:
	var index := api.index
	var first: Variant = HOST if index==0 else GUEST
	var second: Variant = GUEST if index==0 else HOST
	var value := {"api_version":2,"schema_version":2,"room_id":ROOM,"revision":api.revision,"branch":0,"stage_index":index,"level_id":"relay-isles","level_version":2,"definition_hash":Canonical.digest(level),"host_id":HOST,"guest_id":GUEST if api.joined else null,"checkpoint":fixtures[["initial-checkpoint","relay-checkpoint","final-checkpoint"][index]].duplicate(true),"a_turn_id":"t0-%d-a"%index if api.has_a else null,"completed_pair_ids":["p0-0","p0-1"].slice(0,index),"invite_expires_at":"2026-09-21T12:00:00Z","created_at":"2026-09-14T12:00:00Z","updated_at":"2026-09-14T12:00:00Z","active_role":"complete" if index==2 else ("b" if api.has_a else "a"),"first_player_id":null if index==2 else first,"active_player_id":null if index==2 else (second if api.has_a else first),"player_slot":"p0" if owner==HOST else "p1","stage_id":"" if index==2 else level.stages[index].id,"recording_a":fixtures["relay-a" if index==0 else "garden-a"].duplicate(true) if api.has_a else null,"validation":"structural_client_replay_required"}
	if not api.joined and value.active_player_id==GUEST:
		value.active_player_id = null
	if owner==HOST:
		value["invite_code"] = "A1".repeat(10)
	return value

func _server(request: Dictionary, api: FakeApi) -> Dictionary:
	var path: String = request.path
	var body: Dictionary = request.body
	var owner: String = request.owner
	if path=="/v2/capabilities":
		return _ok({"api_version":2,"recording_version":2,"simulation_version":2,"mutations_enabled":api.enabled,"validation":"structural_client_replay_required","chapters":[{"level_id":"relay-isles","level_version":2,"definition_hash":Canonical.digest(level),"premium":false}]})
	if path=="/v2/rooms" and request.method==HTTPClient.METHOD_GET:
		return _ok({"rooms":[_snapshot(api,owner)] if api.exists and (owner==HOST or api.joined) else []})
	if path=="/v2/rooms" and request.method==HTTPClient.METHOD_POST:
		api.creation_keys[body.idempotency_key] = true
		api.exists = true
		return _ok(_snapshot(api,owner))
	if path=="/v2/rooms/join":
		if not api.joined:
			api.joined = true
			api.revision += 1
		var joined_room := _snapshot(api,owner)
		if api.wrong_join:
			joined_room["room_id"] = "X".repeat(22)
		return _ok(joined_room)
	if path=="/v2/rooms/"+ROOM:
		return _ok(_snapshot(api,owner))
	if "/operations/" in path:
		var key := path.get_file()
		return _ok({"receipt":api.receipts[key],"room":_snapshot(api,owner)}) if api.receipts.has(key) else {"ok":false,"status":404,"code":"operation_not_found"}
	if path.ends_with("/turns"):
		var key: String = body.idempotency_key
		if api.receipts.has(key):
			return _ok({"receipt":api.receipts[key],"room":_snapshot(api,owner)})
		var stage_index := api.index
		var record: Dictionary = body.recording
		var hash_input := body.duplicate(true)
		hash_input["operation"] = "turns"
		api.revision += 1
		api.has_a = record.role=="a"
		if record.role=="b":
			api.index += 1
		var receipt := {"schema_version":2,"room_id":ROOM,"idempotency_key":key,"request_hash":Canonical.digest(hash_input),"operation":"turns","accepted_revision":api.revision,"branch":0,"stage_index":stage_index,"stage_id":record.stage_id,"turn_id":"t0-%d-%s"%[stage_index,record.role],"recording_hash":record.recording_hash,"pair_id":"p0-%d"%stage_index if record.role=="b" else null,"checkpoint_hash":fixtures[["initial-checkpoint","relay-checkpoint","final-checkpoint"][api.index]].checkpoint_hash}
		api.receipts[key] = receipt
		return _ok({"receipt":receipt,"room":_snapshot(api,owner)})
	return {"ok":false,"status":404,"code":"not_found","error":"Synthetic missing feature."}

func _adapter_lobby() -> void:
	var api := _api()
	var identity := Identity.new()
	var store := MemoryStore.new()
	var session := Session.new(api,identity.get_value,store)
	api.enabled = false
	_check(await session.load_lobby() and not session.mutations_enabled(),"Capabilities expose an explicit paused service")
	_check((await session.create_room()).is_empty() and api.creation_keys.is_empty(),"Disabled service never receives a create POST")
	api.enabled = true
	_check(await session.load_lobby(),"Matching catalog enables eligible chapter requests")
	store.fail = true
	_check((await session.create_room()).is_empty() and api.creation_keys.is_empty(),"Create is not sent if its key cannot first persist")
	store.fail = false
	api.drop_next = true
	_check((await session.create_room()).is_empty() and not session.pending_lobby().is_empty(),"Accepted create with lost response keeps exact pending request")
	var first: Dictionary = session.pending_lobby()
	session = Session.new(api,identity.get_value,store)
	_check(await session.load_lobby(),"A restarted adapter reloads its own lobby")
	_check(Canonical.same(session.pending_lobby(),first),"Create key and complete body survive restart")
	_check(await session.retry_lobby()==ROOM and api.creation_keys.size()==1,"Retry reuses one create key and verifies the resulting room")
	_check(session.pending_lobby().is_empty() and session.last_room()==ROOM,"Room binding is saved before accepted lobby request is cleared")
	api.hold_next = true
	var result := {"done":false,"value":true}
	_load_into(session,result)
	_check(api.busy,"A real asynchronous adapter call is pending")
	identity.epoch += 1
	identity.ready = false
	session.invalidate_identity()
	api.release.emit()
	await process_frame
	_check(result.done and not result.value and session.room_ids().is_empty(),"Revoked owner callback cannot restore old room list")
	_check(api.calls.back().owner==HOST,"Request headers were captured with the original owner")
	api.queue_free()
	await process_frame

func _adapter_holds() -> void:
	var api := _api()
	var identity := Identity.new()
	var store := MemoryStore.new()
	store.fail_read_scope = "relay-lobby-v2:"+HOST
	var session := Session.new(api,identity.get_value,store)
	_check(not await session.load_lobby() and api.calls.is_empty(),"Unreadable lobby does not dispatch or replace saved state")
	store.fail_read_scope = ""
	_check(await session.load_lobby(),"Same adapter retries a transient lobby read on Refresh")
	_check(await session.create_room()==ROOM,"Hold fixture creates a fully verified room")
	var scope := "relay-room-v2:"+HOST+":"+ROOM
	var saved: Dictionary = store.values[scope].duplicate(true)
	store.fail_read_scope = scope
	session = Session.new(api,identity.get_value,store)
	_check(await session.load_lobby(),"Lobby can load while last room remains unreadable")
	var creations := api.creation_keys.size()
	_check((await session.create_room()).is_empty(),"First create attempt observes unreadable prior room lock")
	_check((await session.create_room()).is_empty() and api.creation_keys.size()==creations,"Repeated create cannot bypass a read-only coordinator")
	_check(not await session.open_room("Z".repeat(22)),"Room switching cannot bypass an unknown saved submission")
	store.fail_read_scope = ""
	_check(await session.open_room(ROOM),"Explicit same-room open retries a recovered disk read")
	store.values[scope]["schema_version"] = 99
	session = Session.new(api,identity.get_value,store)
	_check(await session.load_lobby() and not await session.open_room(ROOM),"Unsupported saved room is held")
	_check((await session.create_room()).is_empty() and not await session.open_room("Z".repeat(22)),"Repeated actions preserve an unsupported room rather than discard its possible lock")
	_check(store.values[scope].schema_version==99,"Unsupported saved bytes were not replaced")
	store.values[scope] = saved
	_check(await session.open_room(ROOM),"Restored compatible room can be reread explicitly")
	var other_room := "Z".repeat(22)
	store.fail_read_scope = "relay-room-v2:"+HOST+":"+other_room
	_check(not await session.open_room(other_room) and session.last_room()==other_room,"Unreadable selected target is recorded before opening it")
	session = Session.new(api,identity.get_value,store)
	_check(await session.load_lobby() and (await session.create_room()).is_empty() and session.last_room()==other_room,"Restart preserves the newly selected room's unknown submission hold")
	_check(not await session.open_room(ROOM),"Restart cannot silently escape the unreadable selected target")
	identity.player = GUEST
	identity.epoch += 1
	api.player_id = GUEST
	session = Session.new(api,identity.get_value,store)
	_check(await session.load_lobby(),"Guest can load independent lobby")
	api.wrong_join = true
	_check((await session.join_room("A1".repeat(10))).is_empty() and not session.pending_lobby().is_empty(),"Wrong invitation-derived room is rejected without clearing request")
	api.wrong_join = false
	_check(await session.retry_lobby()==ROOM,"Correct matching invitation can reconcile the same join")
	api.queue_free()
	await process_frame

func _real_ui_flow() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280,720)
	root.add_child(viewport)
	var app := Main.new()
	var path := "user://relay-online-ui-"+Crypto.new().generate_random_bytes(8).hex_encode()+".json"
	cleanup_paths.append(path)
	app.saves = Save.new(path)
	viewport.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	app.api.queue_free()
	var api := _api()
	root.remove_child(api)
	app.add_child(api)
	app.api = api
	app.identity_read_state = Main.IdentityReadState.LOADED
	app.identity_data = {"player_id":HOST,"device_token":"synthetic-device-token"}
	var store := MemoryStore.new()
	app.relay_session = Session.new(api,app._relay_identity,store)
	var original_solo := Canonical.digest(app.saves.data)
	api.enabled = false
	await app._show_relay_rooms()
	_check(app.mode=="relay_rooms" and _button_named(app,"Create Relay room").disabled,"Real lobby visibly disables creation while live capability is off")
	api.enabled = true
	await app._show_relay_rooms()
	await app._relay_lobby_action("create")
	var preview = app.relay_child
	preview.set_physics_process(false)
	preview.set_process(false)
	await process_frame
	_check(is_instance_valid(preview) and api.get_parent()==app and not app.ui.visible and not app.world.visible,"Online child retains the real main/API owner and hides the old world/UI")
	_check(not app._foreground_refresh_safe(),"Legacy foreground refresh is suspended while the child owns the room")
	app._background_application()
	preview._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	app._resume_application()
	preview._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	_check(app.soundscape.backgrounded and not preview.soundscape.backgrounded,"Android resume keeps retained parent's audio suspended while child owns sound")
	_check(preview.journey==app.relay_session.coordinator and preview.mode=="ready","Online presentation uses tested room coordinator instead of solo save")
	var clipboard := {"calls":0,"text":"unchanged","works":true}
	preview.clipboard_copy = func(text: String):
		clipboard.calls += 1
		if clipboard.works:
			clipboard.text = text
		return clipboard.works
	var copy_status: Label = preview.overlay.find_child("RelayCopyStatus",true,false)
	_check(is_instance_valid(copy_status),"Verified host invitation exposes copy feedback")
	preview._copy_invitation(copy_status)
	_check(clipboard.calls==1 and clipboard.text=="A1".repeat(10) and copy_status.text.begins_with("Invitation code copied"),"Copy uses only the fresh verified invitation and reports successful write")
	clipboard.works = false
	preview._copy_invitation(copy_status)
	_check(copy_status.text.begins_with("Could not copy"),"Clipboard failure never claims successful copy")
	var wrong_invite: Dictionary = preview.journey.snapshot()
	wrong_invite["room_id"] = "Z".repeat(22)
	_check(Session.verified_invitation(wrong_invite,HOST).is_empty() and Session.verified_invitation(preview.journey.snapshot(),GUEST).is_empty(),"Mismatched room and non-host values cannot become clipboard invitations")
	api.drop_next = true
	await _play(preview,"relay-a")
	_check(preview.mode=="online_waiting" and not preview.journey.pending().is_empty(),"Lost commit reply opens receipt-check state without enabling another turn")
	var calls := api.calls.size()
	app._service_foreground_refresh()
	_check(api.calls.size()==calls,"Parent cannot compete with pending online chapter request")
	preview._leave()
	await app._relay_lobby_action("open","Z".repeat(22))
	_check(not is_instance_valid(app.relay_child) and app.mode=="relay_rooms","Blocked room selection never enters a different cached room")
	await app._relay_lobby_action("open",ROOM)
	preview = app.relay_child
	preview.set_physics_process(false)
	preview.set_process(false)
	_check(preview.mode=="online_waiting" and not preview.journey.pending().is_empty(),"Reopening the selected original room retains its exact pending request")
	await preview._online_refresh()
	_check(preview.journey.pending().is_empty() and api.receipts.size()==1,"Receipt check confirms exact original A without duplicate submission")
	preview._leave()
	_check(not is_instance_valid(app.relay_child) and app.ui.visible and app.world.visible,"Leaving child restores parent without replacing API owner")
	# Independent owner-scoped stores and sessions share only the fake server.
	app._invalidate_relay_identity()
	api.player_id = GUEST
	app.identity_data.player_id = GUEST
	app.relay_session = Session.new(api,app._relay_identity,store)
	await app._show_relay_rooms()
	await app._relay_lobby_action("join","A1".repeat(10))
	preview = app.relay_child
	preview.set_physics_process(false)
	preview.set_process(false)
	_check(preview.role=="b" and preview.journey.my_turn(),"Joined friend receives exact earlier ghost as B")
	_check(preview.overlay.find_child("RelayCopyStatus",true,false)==null,"Guest presentation never offers host-only invitation copy")
	await _play(preview,"relay-b")
	_check(preview.mode=="checkpoint" and preview.journey.stage_id()=="garden","Online B advances the verified checkpoint and stops at explicit Continue")
	preview._show_ready()
	_check(preview.role=="a" and preview.journey.snapshot().player_slot=="p1","Next stage alternates roles while keeping guest's physical spirit")
	await _play(preview,"garden-a")
	preview._leave()
	app._invalidate_relay_identity()
	api.player_id = HOST
	app.identity_data.player_id = HOST
	app.relay_session = Session.new(api,app._relay_identity,store)
	await app._show_relay_rooms()
	await app._relay_lobby_action("open",ROOM)
	preview = app.relay_child
	preview.set_physics_process(false)
	preview.set_process(false)
	api.drop_next = true
	await _play(preview,"garden-b")
	_check(preview.mode=="online_waiting" and not preview.journey.pending().is_empty(),"Lost final B reply keeps a receipt-check state")
	preview._leave()
	await app._relay_lobby_action("open",ROOM)
	preview = app.relay_child
	preview.set_physics_process(false)
	preview.set_process(false)
	_check(preview.journey.chapter_complete() and preview.mode=="online_waiting" and _button_named(preview,"Check saved submission")!=null,"Reopened complete snapshot still exposes reconciliation for its pending final turn")
	await preview._online_refresh()
	_check(preview.mode=="complete" and preview._pairs().size()==2 and api.receipts.size()==4,"Both real UI stages complete as exactly four confirmed contributions")
	var writes := store.writes
	preview.replay_pair_index = 0
	preview._play_collection_pair()
	for tick in range(1250):
		if preview.mode!="replay":
			break
		preview._physics_process(1.0/30.0)
	_check(preview.mode=="complete" and store.writes==writes,"Whole online chapter replays both verified pairs without writing progression")
	_check(Canonical.digest(app.saves.data)==original_solo,"Legacy journey, attempts and pending fields remain unchanged by online Relay")
	app._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	_check(app.mode=="relay_online","Retained parent does not also handle child's Android Back")
	preview._leave()
	viewport.queue_free()
	await process_frame

func _play(preview, name: String) -> void:
	preview._begin()
	for input: Dictionary in Simulation.expand_recording_inputs(fixtures[name]):
		preview.advance_input(input)
	preview._finish()
	if preview.mode=="bloom":
		preview._process(2.0)
	_check(preview.mode=="review","Actual input-driven contribution reaches review: "+name)
	await preview._accept()

func _disk_boundaries() -> void:
	var directory := "user://relay-store-"+Crypto.new().generate_random_bytes(8).hex_encode()
	var store := DiskStore.new(directory)
	var scope := "relay-lobby-v2:"+HOST
	_check(store.load_scope(scope)=={"ok":true,"found":false,"value":{}},"Missing scoped file is explicitly absent")
	_check(store.save_scope(scope,{"probe":1}).ok,"Real recoverable adapter writes separate local generation")
	var path := directory.path_join(scope.sha256_text()+".json")
	cleanup_paths.append(path)
	_check(Canonical.same(DiskStore.new(directory).load_scope(scope).value,{"probe":1}),"Fresh adapter reloads actual persisted JSON")
	_check(not store.save_scope("../../journey",{}).ok,"Arbitrary file paths cannot escape the scope mapping")
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	raw.version = 99
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(raw))
	file.close()
	var before := FileAccess.get_file_as_string(path)
	var future := DiskStore.new(directory)
	_check(not future.load_scope(scope).ok and not future.save_scope(scope,{}).ok and FileAccess.get_file_as_string(path)==before,"Future generation is preserved rather than overwritten with fresh state")

func _load_into(session, result: Dictionary) -> void:
	result.value = await session.load_lobby()
	result.done = true

func _button_named(app, text: String) -> Button:
	for button: Button in app.overlay.find_children("*","Button",true,false):
		if button.text==text:
			return button
	return null

func _ok(data: Dictionary) -> Dictionary:
	return {"ok":true,"status":200,"data":data}

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
